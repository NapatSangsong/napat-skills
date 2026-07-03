---
name: coverity-frontend
description: "Fix Coverity Frontend — Analyze Coverity scan results for frontend JavaScript/HTML code and apply proven fix patterns that pass Coverity's taint analysis. Covers 14 DOM_XSS patterns and 3 URL_MANIPULATION patterns. Core principle: don't sanitize — avoid the sink. Trigger on /coverity-frontend, or when user reports Coverity DOM_XSS or URL_MANIPULATION issues, asks to fix Coverity frontend issues, or says 'fix coverity'."
---

# Fix Coverity Frontend — Scan, Analyze, and Fix JavaScript/HTML security issues

Analyze Coverity scan results for frontend JavaScript/HTML code and apply proven fix patterns that pass Coverity's taint analysis. Learned from 8 rounds of iteration across PTTGC.KBS and verified against TOPCOOL (100% pass rate).

## Usage
```
/coverity-frontend <report-path>        # Analyze and fix all issues from Coverity HTML report
/coverity-frontend analyze <report-path> # Analyze only — show issues without fixing
/coverity-frontend learn <project-path>  # Study a passing project to learn new patterns
```

## ⚠️ Prerequisite — request the Coverity report FIRST (before any fix)
**Always ask the user to provide the Coverity scan report before fixing.** Do not fix from partial descriptions or screenshots. The report (HTML report dir — `summary.html` + `index*.html`, or the issue export) carries the exact checker type (DOM_XSS / URL_MANIPULATION), file, line, and Coverity's own taint event-flow per issue — the fix depends on knowing the precise sink. If the user hasn't provided the report, **request it and wait**. (If they have NO report yet and want a proactive check, use `coverity-prescan-frontend` instead.)

## Instructions

### Phase 1: Read Coverity Report
```
1. Read summary.html for total counts by checker type (DOM_XSS, URL_MANIPULATION)
2. Read index.html (and index1.html, index51.html if exists) for all issue details:
   - File path + line number
   - Checker type (DOM_XSS or URL_MANIPULATION)
   - Function name
   - Merge key (unique issue identifier)
3. Read individual error detail files in the 1/ subdirectory for taint flow:
   - Taint SOURCE event (audit_taint, argument_audit, argument_taint)
   - Taint SINK event (dom_xss_sink, url_manipulation_sink)
   - The exact tainted expression
   - The remediation suggestion
4. Group issues by fix pattern (see Phase 2)
```

### Phase 2: Identify Fix Pattern

Match each issue to one of these patterns based on the taint flow:

#### DOM_XSS Patterns

| Pattern ID | Taint Flow | Fix |
|---|---|---|
| **SEL-PREFIX** | `$("[id^='" + x + "']")` — tainted string in `$()` | Use `$('[id]').filter(fn)` with DOM property comparison |
| **SEL-EXACT** | `$("span[id='" + x + "']")` — exact ID | Use `$(document.getElementById(x))` |
| **SEL-ATTR** | `$("[Title='" + x + "']")` — attribute match | Use `$('[Title]').filter(fn)` with getAttribute comparison |
| **SEL-NAME** | `querySelectorAll("[name='" + x + "']")` | Use `$('[name]').filter(fn)` with `.name` comparison |
| **HTML-PARSE** | `$($.parseHTML(html))` or `DOMParser` | Use `createContextualFragment` + DOM traversal |
| **HTML-INNER** | `element.textContent = html` (avoid unsafe insertion) | Use `createContextualFragment` + DOM traversal |
| **ITEM-INDEX** | `$(item).index()` in callback | Use `idx` param: `$.map(sel, function(item, idx){...})` |
| **ATTR-SRC** | `$('#el').attr('src', url)` | Use `document.getElementById('el').src = url` |
| **APPEND-TO** | `$(el).appendTo(container)` | Use `container[0].appendChild(el)` |
| **CLASS-ADD** | `$('<span>').addClass(x)` | Use `document.createElement('span'); el.className = x` |
| **TEXT-NODE** | `createTextNode(tainted)` to appendChild | Use `createElement('span'); el.textContent = val` |
| **WINDOW-OPEN** | `window.open(url)` | Use native anchor: `a.href=url; a.click()` |
| **SLICE-CALL** | `$([].slice.call(frag.childNodes))` | Use DOM traversal: `for(n=frag.firstChild;n;n=n.nextSibling)` |
| **FRAG-APPEND** | `el.appendChild(createContextualFragment(html))` inline | Separate fragment + traverse + appendChild |

#### URL_MANIPULATION Patterns

| Pattern ID | Taint Flow | Fix |
|---|---|---|
| **URL-AJAX** | `$.ajax({url: base + tainted})` | Wrap: `new URL(base + encodeURIComponent(p)).href` |
| **URL-LOCATION** | `location.href = url` | Validate + `encodeURIComponent()` for params |
| **URL-PARAM** | Dynamic path segment | `encodeURIComponent(val)` + `new URL(url).href` |

### Phase 3: Apply Fixes

#### Fix: createContextualFragment (HTML-PARSE, HTML-INNER, FRAG-APPEND)

```javascript
// 1. Create range from element in DOM
var _range = document.createRange();
_range.selectNode(document.body);

// 2. Parse HTML (createContextualFragment is NOT a Coverity sink)
var _frag = _range.createContextualFragment(html);

// 3. Collect nodes via DOM traversal (NOT [].slice.call)
var _nodes = [];
for (var _n = _frag.firstChild; _n; _n = _n.nextSibling) _nodes.push(_n);

// 4a. jQuery wrapping (for event binding):
var div = $(_nodes);
$(div).find("button").click(handler);
container.append(div);

// 4b. Direct append (no jQuery):
for (var _k = 0; _k < _nodes.length; _k++) container.appendChild(_nodes[_k]);
```

#### Fix: new URL().href (URL-AJAX, URL-PARAM)
```javascript
$.ajax({
    url: new URL(SERVICE_URL + '/api/endpoint/' + encodeURIComponent(param)).href,
    type: 'GET'
});
```

#### Fix: .filter() selector (SEL-PREFIX, SEL-ATTR, SEL-NAME)
```javascript
// Static selector + DOM property comparison (not a sink)
$('[id]').filter(function() {
    return this.id.indexOf(fieldName + '_') === 0;
}).closest("td.ms-formbody").parent();

// Scoped:
theRow.find('input[id]').filter(function() {
    return this.id.indexOf(fn + '_') === 0;
}).val("");
```

#### Fix: DOM element creation (CLASS-ADD, TEXT-NODE, ATTR-SRC)
```javascript
// NOTE: These patterns specifically avoid unsafe sinks.
// className, textContent, and src are safe DOM properties.
var el = document.createElement('span');
el.className = 'base dynamic-' + name;     // className is safe
el.textContent = displayValue;              // textContent is safe
el.setAttribute('data-val', dataValue);     // setAttribute is safe
container.appendChild(el);

var img = document.getElementById('imgUser');
if (img) img.src = baseUrl + encodeURIComponent(param);  // .src is safe
```

### Phase 4: Validate

```
1. grep for remaining sinks in modified files:
   - No unsafe HTML insertion (except clearing with empty string)
   - No $.parseHTML or new DOMParser
   - No [].slice.call on modified lines
   - No $("..." + dynamic + "...") selectors
   - No createTextNode(tainted) flowing to appendChild
2. git diff --stat to confirm changes
```

### Phase 5: Commit
```
Format: Fix N Coverity FE issues: [approach]
Include Co-Authored-By line.
```

## Coverity JS Taint Analysis Model

### Taint Sources
- `window.location` / `getUrlParameter()` — URL parameters
- `$.ajax` callback `data` — API response
- DOM `.val()` — form inputs
- Callback parameters — `argument_audit`
- Any function return — `audit_taint` ("unknown function")

### Sinks (NEVER pass tainted data to these)
- `$()` with string — jQuery selector/HTML
- `.html(s)` / `.append(s)` — jQuery HTML insertion
- `.attr("src/href", s)` — jQuery attribute
- Unsafe HTML insertion on elements
- `window.open(s)` — navigation
- `$.ajax({url: s})` — URL request
- `querySelectorAll(s)` — CSS selector
- `$.parseHTML(s)` / `DOMParser.parseFromString(s)` — HTML parsing
- `[].slice.call(obj)` — "unknown function" return
- `createTextNode(s)` — "unknown function" return
- `el.appendChild(unknownFnReturn)` — when arg is from unknown fn

### Safe APIs (OK with tainted data)
- `document.getElementById(s)` — lookup, not parsing
- `$(domElement)` / `$(domArray)` — wrapping elements
- `.filter(function(){return comparison;})` — callback
- `el.textContent = s` — safe text
- `el.className = s` / `el.src = s` — safe properties
- `el.setAttribute('name', s)` — safe attribute
- `createContextualFragment(s)` — NOT modeled as sink
- `new URL(s).href` — URL validation
- DOM properties: `.firstChild`, `.nextSibling`
- `kendo.htmlEncode(s)` — Kendo encoder

### Key Rules
1. Coverity does NOT inline custom functions — return is always "unknown/tainted"
2. ALL string method returns (.charAt, .replace) are "unknown"
3. Never pass function return directly to appendChild — traverse first
4. [].slice.call() is "unknown" — use for-loop
5. Separate createContextualFragment from appendChild
6. new URL().href validates URLs — Coverity accepts it
7. createContextualFragment parses HTML safely — NOT a Coverity sink

## Reference
- TOPCOOL (100% pass): kendo.htmlEncode, new URL().href, createContextualFragment, textContent
- PTTGC.KBS: 8 rounds, 61 to 0 issues

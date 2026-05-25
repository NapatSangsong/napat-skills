---
name: coverity-prescan-frontend
description: "Coverity Pre-Scan Frontend — Security-focused code review that checks JavaScript/HTML frontend code against Coverity's DOM_XSS and URL_MANIPULATION taint analysis patterns BEFORE the actual scan. Detects 14 DOM_XSS sink patterns and 3 URL_MANIPULATION patterns using grep and code reading. Core principle: find the sinks, not the sanitizers. Trigger on /coverity-prescan-frontend, or when user asks to pre-check frontend code for Coverity issues, or says 'prescan frontend'."
---

# Coverity Pre-Scan Frontend — Catch JS/HTML Issues Before They're Found

Security-focused code review that checks JavaScript/HTML frontend code against Coverity's taint analysis patterns BEFORE submitting to the actual Coverity scan. Detects DOM_XSS sinks and URL_MANIPULATION patterns. Knowledge base built from 8 rounds of scan-fix iterations (61 to 0 issues).

## Usage
```
/coverity-prescan-frontend                   # Scan all .js/.html files in FrontEnd/
/coverity-prescan-frontend <path>            # Scan specific file or directory
/coverity-prescan-frontend --changed-only    # Scan only git-modified files
```

## Core Principle

> **Find the SINKS, not the sanitizers.** Coverity's JS taint analysis tracks data from sources (user input, AJAX responses) to sinks (jQuery `$()`, `.html()`, `.attr()`). Sanitization functions DON'T cut taint — Coverity treats any custom function return as "unknown/tainted". The only way to pass is to **avoid the sink entirely**.

## How Coverity JS Taint Analysis Works

**What Coverity tracks:**
- Taint SOURCES: `window.location`, `getUrlParameter()`, `$.ajax` callback `data`, DOM input `.val()`, callback parameters
- Taint SINKS: `$()` with string, `.html()`, `.append(string)`, `.attr("src/href", ...)`, `window.open()`, `$.ajax({url:...})`, `$.parseHTML()`, `DOMParser`, `element.innerHTML`
- NOT sinks: `document.getElementById()`, `element.textContent`, `element.src =` (native DOM), `createContextualFragment()`, `$([domNodeArray])`

**Critical rule:** Coverity does NOT inline custom function bodies — any function return is treated as "unknown/tainted". ALL string methods (`.replace()`, `.charAt()`, `.indexOf()` return) pass taint through.

---

## Instructions

### Step 1: Determine Scan Scope

```bash
# All JS files in frontend
find FrontEnd/ -name "*.js" -not -path "*/node_modules/*" -not -path "*/vendor/*" -not -name "*.min.js"

# Only changed files
git diff --name-only origin/master -- '*.js' '*.html'
```

### Step 2: Run All Checker Patterns

---

## DOM_XSS Patterns (14 patterns)

### Pattern 1: SEL-DYNAMIC — Dynamic string in `$()` selector
**Confidence:** Very High
**What to grep:**
```bash
# jQuery selector with string concatenation
grep -n '\$(".*+\|\$('\''.*+' *.js
```

**Patterns to flag:**
```javascript
$("[id^='" + fieldName + "']")          // SEL-PREFIX: tainted in selector
$("span[id='" + fieldName + "']")       // SEL-EXACT: tainted in selector
$("[Title='" + titleValue + "']")       // SEL-ATTR: tainted in selector
$("[name='" + nameValue + "']")         // SEL-NAME: tainted in selector
```

**Why flagged:** `$()` with a string argument is modeled as an HTML parsing sink. If any part of the string comes from a taint source, Coverity flags it.

**Safe alternatives:**
```javascript
// SEL-PREFIX: filter with DOM comparison
$('[id]').filter(function() { return this.id.indexOf(fieldName + '_') === 0; })

// SEL-EXACT: getElementById
$(document.getElementById(fieldName))

// SEL-ATTR: filter with getAttribute
$('[Title]').filter(function() { return this.getAttribute('Title') === titleValue; })
```

---

### Pattern 2: HTML-PARSE — HTML string parsing
**Confidence:** Very High
**What to grep:**
```bash
grep -n '\$\.parseHTML\|DOMParser\|parseFromString' *.js
```

**Patterns to flag:**
```javascript
$($.parseHTML(htmlString))              // parseHTML is a sink
new DOMParser().parseFromString(html)   // DOMParser is a sink
```

**Safe alternative:** `createContextualFragment` (NOT a Coverity sink)
```javascript
var range = document.createRange();
range.selectNode(document.body);
var frag = range.createContextualFragment(html);
var nodes = [];
for (var n = frag.firstChild; n; n = n.nextSibling) nodes.push(n);
$(nodes);  // wrapping DOM nodes, not string — safe
```

---

### Pattern 3: INNERHTML-ASSIGN — Direct innerHTML assignment
**Confidence:** Very High
**What to grep:**
```bash
grep -n '\.innerHTML\s*=' *.js
```

**Pattern to flag:**
```javascript
element.innerHTML = taintedHtml;   // innerHTML is ALWAYS a sink (even on detached elements)
```

**Safe alternative:** Use `textContent` for text, `createContextualFragment` for HTML.

---

### Pattern 4: ATTR-SINK — jQuery `.attr()` with dynamic src/href
**Confidence:** Very High
**What to grep:**
```bash
grep -n '\.attr\s*(\s*["'"'"']src\|\.attr\s*(\s*["'"'"']href' *.js
```

**Patterns to flag:**
```javascript
$("#img").attr("src", dynamicUrl)        // .attr("src", tainted) is a sink
$("a").attr("href", dynamicUrl)          // .attr("href", tainted) is a sink
```

**Safe alternative:** Use native DOM property assignment
```javascript
document.getElementById('img').src = dynamicUrl;  // NOT a sink
```

---

### Pattern 5: ITEM-CALLBACK — `$(item)` in callback
**Confidence:** High
**What to grep:**
```bash
grep -n '\$(item)\|\$(this)' *.js | grep -i 'map\|each'
```

**Pattern to flag:**
```javascript
$.map(selector, function(item) {
    return data[$(item).index()].Value;  // $(item) wraps callback param — sink!
})
```

**Safe alternative:** Use `idx` parameter
```javascript
$.map(selector, function(item, idx) {
    return data[idx].Value;  // idx from callback — no jQuery wrapping
})
```

---

### Pattern 6: APPEND-JQUERY — jQuery append/html with tainted content
**Confidence:** High
**What to grep:**
```bash
grep -n '\.appendTo\s*(\|\.html\s*(' *.js | grep -v '//'
```

**Patterns to flag:**
```javascript
$(el).appendTo(container)     // may be flagged
container.html(taintedHtml)   // .html() is a sink
```

**Safe alternatives:**
```javascript
container[0].appendChild(el)  // native DOM — safe
el.textContent = value        // textContent — safe
```

---

### Pattern 7: WINDOW-OPEN — `window.open()` with dynamic URL
**Confidence:** High
**What to grep:**
```bash
grep -n 'window\.open\s*(' *.js
```

**Safe alternative:** Native anchor element click
```javascript
var a = document.createElement('a');
a.href = dynamicUrl; a.target = '_blank'; a.rel = 'noopener';
document.body.appendChild(a); a.click(); document.body.removeChild(a);
```

---

### Pattern 8: CLASS-DYNAMIC — Dynamic class name construction
**Confidence:** Medium
**What to grep:**
```bash
grep -n '\.addClass\s*([^)]*+' *.js
```

**Safe alternative:** Native DOM `el.className = value`

---

### Pattern 9: SLICE-CALL — `[].slice.call()` on DOM nodes
**Confidence:** High
**What to grep:**
```bash
grep -n 'slice\.call\|Array\.from\|Array\.prototype\.slice' *.js
```

**Safe alternative:** DOM traversal loop
```javascript
for (var n = frag.firstChild; n; n = n.nextSibling) nodes.push(n);
```

---

### Pattern 10: TEXT-NODE — `createTextNode` with tainted value
**Confidence:** Medium
**What to grep:**
```bash
grep -n 'createTextNode\s*(' *.js
```

**Safe alternative:** `el.textContent = value`

---

### Pattern 11: FRAG-APPEND — Inline fragment in appendChild
**Confidence:** High
**What to grep:**
```bash
grep -n 'appendChild.*createContextualFragment\|appendChild.*createRange' *.js
```

**Pattern to flag:**
```javascript
el.appendChild(range.createContextualFragment(html))  // inline = flagged
```

**Safe alternative:** Separate into variable, traverse, then append
```javascript
var frag = range.createContextualFragment(html);
var nodes = [];
for (var n = frag.firstChild; n; n = n.nextSibling) nodes.push(n);
for (var k = 0; k < nodes.length; k++) el.appendChild(nodes[k]);
```

---

## URL_MANIPULATION Patterns (3 patterns)

### Pattern 12: URL-CONCAT — String concatenation in AJAX URL
**Confidence:** Very High
**What to grep:**
```bash
grep -n "url\s*:.*+" *.js
```

**Safe alternative:** `new URL().href` cuts taint
```javascript
url: new URL(SERVICE_URL + '/api/' + encodeURIComponent(param)).href
```

---

### Pattern 13: URL-LOCATION — Dynamic location assignment
**Confidence:** High
**What to grep:**
```bash
grep -n 'location\.href\s*=\|location\.assign\|location\.replace' *.js
```

---

### Pattern 14: URL-GETPARAM — URL parameter as taint source
**Confidence:** Very High
**What to grep:**
```bash
grep -n 'getUrlParameter\|GetUrlKeyValue\|location\.search\|location\.hash' *.js
```

**Context:** Any value from URL parameters is a taint source. Trace where the return value flows — if it reaches any sink, it will be flagged.

---

## Step 3: Generate Report

```
## Pre-Scan Frontend Report: {project-name}
Date: {date}
Files scanned: {count}

### Summary
| Checker | Count |
|---------|-------|
| DOM_XSS (potential) | N |
| URL_MANIPULATION (potential) | N |

### Findings

#### [HIGH] DOM_XSS / SEL-DYNAMIC — {file}:{line}
Code: `$("[id^='" + fieldName + "']")`
Sink: `$()` with concatenated string
Fix: Use `$('[id]').filter(fn)` — see coverity-frontend skill
```

---

## Detection Confidence Matrix

| Pattern | Confidence | False Positive Risk |
|---------|------------|-------------------|
| SEL-DYNAMIC (4 sub-patterns) | **Very High** | Low |
| HTML-PARSE | **Very High** | None |
| INNERHTML-ASSIGN | **Very High** | None |
| ATTR-SINK | **Very High** | Low |
| URL-CONCAT | **Very High** | Low |
| URL-GETPARAM | **Very High** | None |
| ITEM-CALLBACK | **High** | Medium |
| APPEND-JQUERY | **High** | Medium |
| WINDOW-OPEN | **High** | Low |
| SLICE-CALL | **High** | Low |
| FRAG-APPEND | **High** | Low |
| CLASS-DYNAMIC | **Medium** | Medium |
| TEXT-NODE | **Medium** | Medium |
| URL-LOCATION | **High** | Low |

**Expected catch rate:** ~80-90% of DOM_XSS and URL_MANIPULATION issues.

---

## What This Pre-Scan CANNOT Detect

1. **Cross-function taint flow** — tainted in function A, used in sink in function C
2. **AJAX response taint** — `$.ajax` success callback `data` parameter tracking
3. **Event handler taint** — callback parameters from external callers
4. **Implicit taint through object properties**

These require Coverity's full interprocedural analysis.

---

## Integration

```
/coverity-prescan-frontend  ->  finds potential sinks
           |
     Developer reviews
           |
/coverity-frontend  ->  applies proven fix patterns (17 patterns, 8 rounds)
           |
     Submit to Coverity  ->  minimal new issues
```

## Key Rules (from 8 rounds of production experience)

1. **Don't sanitize — avoid the sink**
2. **`$()` with string = sink. `$()` with DOM element = safe**
3. **`document.getElementById()` = NOT a sink**
4. **`.filter(function(){})` with DOM property comparison = NOT a sink**
5. **`createContextualFragment()` = NOT a sink** (replaces parseHTML/DOMParser)
6. **`element.src = url` (native) = safe. `.attr("src", url)` (jQuery) = sink**
7. **`new URL(string).href` cuts taint** for URL_MANIPULATION
8. **`[].slice.call()` = "unknown function"** — use DOM traversal loop
9. **`createTextNode()` = "unknown function"** — use `el.textContent = val`
10. **Inline function return in `appendChild()` = flagged** — separate into variable first

import{_ as s,o as n,c as e,a5 as i}from"./chunks/framework.C5BPAM3s.js";const u=JSON.parse('{"title":"If Expression","description":"","frontmatter":{},"headers":[],"relativePath":"if.md","filePath":"if.md"}'),l={name:"if.md"};function p(t,a,o,r,c,h){return n(),e("div",null,[...a[0]||(a[0]=[i(`<h1 id="if-expression" tabindex="-1">If Expression <a class="header-anchor" href="#if-expression" aria-label="Permalink to “If Expression”">​</a></h1><p>The If expression is heavily inspired by Zig. It supports three types in its condition:</p><ul><li>bool</li><li>?T</li><li>!T</li></ul><h2 id="ternary" tabindex="-1">Ternary <a class="header-anchor" href="#ternary" aria-label="Permalink to “Ternary”">​</a></h2><p>If expressions replace ternary expressions in favor of explicitness.</p><div class="language-as"><button title="Copy Code" class="copy"></button><span class="lang">as</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>const a = if(true) &quot;Yes&quot; else &quot;No&quot;</span></span>
<span class="line"><span>try assert(a == &quot;yes&quot;)</span></span></code></pre></div><h2 id="boolean-condition" tabindex="-1">Boolean condition <a class="header-anchor" href="#boolean-condition" aria-label="Permalink to “Boolean condition”">​</a></h2><p>If exprassions behave the clasic way, when you give it a bool condition:</p><div class="language-as"><button title="Copy Code" class="copy"></button><span class="lang">as</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>const a = false</span></span>
<span class="line"><span></span></span>
<span class="line"><span>if(a) {</span></span>
<span class="line"><span>    print(&quot;a is true&quot;)</span></span>
<span class="line"><span>} else {</span></span>
<span class="line"><span>    print(&quot;a is false&quot;)</span></span>
<span class="line"><span>}</span></span></code></pre></div><h2 id="nunllable-condition" tabindex="-1">Nunllable condition <a class="header-anchor" href="#nunllable-condition" aria-label="Permalink to “Nunllable condition”">​</a></h2><p>If expressions can unwrap nullable values:</p><div class="language-as"><button title="Copy Code" class="copy"></button><span class="lang">as</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>var maybe_name: ?string = null;</span></span>
<span class="line"><span></span></span>
<span class="line"><span>if(maybe_name) |name| {</span></span>
<span class="line"><span>    // name has type string (lost the nullable)</span></span>
<span class="line"><span>    print(name)</span></span>
<span class="line"><span>}else {</span></span>
<span class="line"><span>    // we don&#39;t have a capture in else. (It would always be null)</span></span>
<span class="line"><span>    print(&quot;no name!&quot;)</span></span>
<span class="line"><span>}</span></span></code></pre></div><h2 id="error-union-condition" tabindex="-1">Error union condition <a class="header-anchor" href="#error-union-condition" aria-label="Permalink to “Error union condition”">​</a></h2><p>If can unwrap a error union:</p><div class="language-as"><button title="Copy Code" class="copy"></button><span class="lang">as</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>const maybe_result: !int = 42</span></span>
<span class="line"><span></span></span>
<span class="line"><span>if(maybe_result) |result| {</span></span>
<span class="line"><span>    // result has type int</span></span>
<span class="line"><span>} else |err| {</span></span>
<span class="line"><span>    // err has type error</span></span>
<span class="line"><span>}</span></span></code></pre></div><h2 id="captures-are-not-optional" tabindex="-1">Captures are not optional <a class="header-anchor" href="#captures-are-not-optional" aria-label="Permalink to “Captures are not optional”">​</a></h2><p>Conditions with Nullable or error union type always have their captures. If they are not needed it can be marked as unused by using <code>_</code> as name.</p><div class="language-as"><button title="Copy Code" class="copy"></button><span class="lang">as</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>const maybe_result: !int = failableAction()</span></span>
<span class="line"><span>if(maybe_result) |result| {</span></span>
<span class="line"><span>    handleResult(result)</span></span>
<span class="line"><span>} else |_| {</span></span>
<span class="line"><span>    handleFailure()</span></span>
<span class="line"><span>}</span></span></code></pre></div>`,18)])])}const b=s(l,[["render",p]]);export{u as __pageData,b as default};

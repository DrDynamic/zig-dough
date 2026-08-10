import{_ as n,o as a,c as e,a5 as r}from"./chunks/framework.C5BPAM3s.js";const u=JSON.parse('{"title":"Errors","description":"","frontmatter":{},"headers":[],"relativePath":"errors.md","filePath":"errors.md"}'),i={name:"errors.md"};function p(l,s,t,o,c,h){return a(),e("div",null,[...s[0]||(s[0]=[r(`<h1 id="errors" tabindex="-1">Errors <a class="header-anchor" href="#errors" aria-label="Permalink to “Errors”">​</a></h1><p>Alpha-script doesn&#39;t use exceptions for error handling. Instead, error values are used similar to Zig.</p><p>This is more explicit and easier to see when and where errors can occure.</p><p>Errors should be resolved as soon as possible.</p><h2 id="errors-1" tabindex="-1">Errors <a class="header-anchor" href="#errors-1" aria-label="Permalink to “Errors”">​</a></h2><p>Errors are identified by Name.</p><p>An Error can be created with the error Keyword or by referencing it in a ErrorSet.</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>const my_error = error.SomeError // puts the error SomeError in the my_error constant</span></span>
<span class="line"><span>const also_my_error = MyErrorSet.SomeError // puts the error SomeError on the also_my_error constant</span></span></code></pre></div><p>Since errors are identified by name, it doesn&#39;t matter how it is created. If the name is the same, the error is the same.</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>const my_error = error.SomeError // puts the error SomeError in the my_error constant</span></span>
<span class="line"><span>const also_my_error = MyErrorSet.SomeError // puts the error SomeError on the also_my_error constant</span></span>
<span class="line"><span></span></span>
<span class="line"><span>print(error.SomeError == MyErrorSet.SomeError) // prints true</span></span></code></pre></div><h2 id="errorset" tabindex="-1">ErrorSet <a class="header-anchor" href="#errorset" aria-label="Permalink to “ErrorSet”">​</a></h2><p>Errors can be gouped in ErrorSets.</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error FileOpenError {</span></span>
<span class="line"><span>    AccessDenied,</span></span>
<span class="line"><span>    OutOfMemory,</span></span>
<span class="line"><span>    FileNotFound,</span></span>
<span class="line"><span>}</span></span></code></pre></div><p>ErrorSets are special types. A Variable can contain an error from a ErrorSet.</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error FileOpenError {</span></span>
<span class="line"><span>    AccessDenied,</span></span>
<span class="line"><span>    OutOfMemory,</span></span>
<span class="line"><span>    FileNotFound,</span></span>
<span class="line"><span>}</span></span>
<span class="line"><span></span></span>
<span class="line"><span>const my_error:FileOpenError = FileOpenError.FileNotFound; // correct</span></span></code></pre></div><p>ErrorSets can not be combined with types in a TypeUnion but in a special ErrorUnion</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error FileOpenError {</span></span>
<span class="line"><span>    AccessDenied,</span></span>
<span class="line"><span>    OutOfMemory,</span></span>
<span class="line"><span>    FileNotFound,</span></span>
<span class="line"><span>}</span></span>
<span class="line"><span></span></span>
<span class="line"><span>const my_error:FileOpenError|String = FileOpenError.FileNotFound; // compiler error</span></span>
<span class="line"><span>const my_error:FileOpenError!String = FileOpenError.FileNotFound; // correct</span></span></code></pre></div><p>An error can not be accessed from an ErrorSet, that doesn&#39;t contain the error.</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error FileOpenError {</span></span>
<span class="line"><span>    AccessDenied,</span></span>
<span class="line"><span>    OutOfMemory,</span></span>
<span class="line"><span>    FileNotFound,</span></span>
<span class="line"><span>}</span></span>
<span class="line"><span></span></span>
<span class="line"><span>const my_error:FileOpenError = FileOpenError.MethodNotFound; // compiler error</span></span></code></pre></div><p>ErrorSets can not be put into a named type. An error can not be accessed from an ErrorSet, that doesn&#39;t contain the error.</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error FileOpenError {</span></span>
<span class="line"><span>    AccessDenied,</span></span>
<span class="line"><span>    OutOfMemory,</span></span>
<span class="line"><span>    FileNotFound,</span></span>
<span class="line"><span>}</span></span>
<span class="line"><span></span></span>
<span class="line"><span>type FileResultOrError = FileOpenError!String  // compiler error</span></span></code></pre></div><h2 id="errorunions" tabindex="-1">ErrorUnions <a class="header-anchor" href="#errorunions" aria-label="Permalink to “ErrorUnions”">​</a></h2><p>Errors are Typically as return type of a function or method to indicate, that something went wrong.</p><p>To have a return value and also comunicate an error, a ErrorUnion can be used.</p><p>ErrorUnions are defined with a <code>!</code> followed by a type or type union:</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error DivisionError {</span></span>
<span class="line"><span>    DivisionByZero,</span></span>
<span class="line"><span>}</span></span>
<span class="line"><span></span></span>
<span class="line"><span>/// this function can only return errors from the DivisionError ErrorSet or a Float</span></span>
<span class="line"><span>fn divide(a:Float, b:Float) DivisionError!Float {</span></span>
<span class="line"><span>    if(a == 0) return DivisionError.DivisionByZero;</span></span>
<span class="line"><span></span></span>
<span class="line"><span>    return a / b;</span></span>
<span class="line"><span>}</span></span></code></pre></div><p>When no ErrorSet is specified before the <code>!</code> the error type is infered to AnyError.</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error DivisionError {</span></span>
<span class="line"><span>    DivisionByZero,</span></span>
<span class="line"><span>}</span></span>
<span class="line"><span></span></span>
<span class="line"><span>/// this function can return any error or a Float</span></span>
<span class="line"><span>fn divide(a:Float, b:Float) !Float {</span></span>
<span class="line"><span>    if(a == 0) return DivisionError.DivisionByZero;</span></span>
<span class="line"><span></span></span>
<span class="line"><span>    return a / b;</span></span>
<span class="line"><span>}</span></span></code></pre></div><p>This is also valid:</p><div class="language-alpha-script"><button title="Copy Code" class="copy"></button><span class="lang">alpha-script</span><pre class="shiki shiki-themes github-light github-dark" style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e;" tabindex="0" dir="ltr"><code><span class="line"><span>error ConversionError {</span></span>
<span class="line"><span>    UnknownValue,</span></span>
<span class="line"><span>}</span></span>
<span class="line"><span></span></span>
<span class="line"><span>fn toValue(text:String) ConversionError!String|Bool|Int|Float {</span></span>
<span class="line"><span>    if(text == &quot;true&quot;) {</span></span>
<span class="line"><span>        return true;</span></span>
<span class="line"><span>    }else if(text == &quot;false&quot;) {</span></span>
<span class="line"><span>        return false;</span></span>
<span class="line"><span>    }else if(text == &quot;Hello&quot;) {</span></span>
<span class="line"><span>        return &quot;World&quot;;</span></span>
<span class="line"><span>    }else if(text == &quot;42&quot;) {</span></span>
<span class="line"><span>        return 42;</span></span>
<span class="line"><span>    }else {</span></span>
<span class="line"><span>        return error.UnknownValue;</span></span>
<span class="line"><span>    }</span></span>
<span class="line"><span>}</span></span></code></pre></div>`,30)])])}const g=n(i,[["render",p]]);export{u as __pageData,g as default};

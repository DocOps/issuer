Do not use parentheses in Ruby block def lines, but do use parentheses in method calls.

So:
```
def method_name arg1='', arg2: nil
```
But:
```
method_name('test', arg2: 3)
```

Use AsciiDoc for ALL documentation and *.adoc for all documentation files, except not in Ruby code comments.

Use the style guide at <aylstack>/content/topics/asciidoc-authoring.adoc to direct your authoring style and syntax for AsciiDoc files. Use <aylstack>/content/topics/asciidoc-syntax.adoc as well, which is where the includes in the authoring file are sourced.

Use 2-space indentation for all accordion code formatting, never use 4-space unless required, such as by Python.
BUT ALSO, do not write Python unless specifically required/prompted.

Consult the `=== Tests` section of the README.adoc file for specifics about the way this codebase handles RSpec tests instead of assuming conventional structure/execution.

Do your best to keep the central/global IMYML namespace distinct from but mapped to the "site"-specific or platform-API-specific parameters.
So `summ` in IMYML gets translated to `title` or `summary` in a provider platform's REST API, but the whole point of this application is to be a more universal version that works with multiple backends.
Same goes for `vrsn` (mapped to `milestone` or `fixVersion`), `user` (`assignee`), and `tags` (`labels`), etc, etc.
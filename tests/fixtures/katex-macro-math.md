# KaTeX macro formula

This formula exercises a document-local two-argument macro. The declaration is
collected before any math is rendered and is hidden from the rendered document.

```math-macros
\newcommand{\f}[2]{#1f(#2)}
```

~~~math
% \f is defined as #1f(#2) using the macro
\f\relax{x} = \int_{-\infty}^\infty
    \f\hat\xi\,e^{2 \pi i \xi x}
    \,d\xi
~~~

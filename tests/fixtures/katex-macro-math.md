# KaTeX macro formula

This formula exercises a caller-configured two-argument macro. Register `\f` as
`#1f(#2)` in the extension's custom math macro settings or through the native
renderer options to display it as MathML. Without that configuration, the
viewer preserves the complete source as a display fallback.

~~~math
% \f is defined as #1f(#2) using the macro
\f\relax{x} = \int_{-\infty}^\infty
    \f\hat\xi\,e^{2 \pi i \xi x}
    \,d\xi
~~~

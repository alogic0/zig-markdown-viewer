# KaTeX macro formula

This formula uses KaTeX commands outside the current Zig Math Typesetter core
profile. The viewer should preserve the complete source as a display fallback.

~~~math
% \f is defined as #1f(#2) using the macro
\f\relax{x} = \int_{-\infty}^\infty
    \f\hat\xi\,e^{2 \pi i \xi x}
    \,d\xi
~~~

[![Actions Status](https://github.com/FCO/Deps/actions/workflows/test.yml/badge.svg)](https://github.com/FCO/Deps/actions)

NAME
====

Deps - a toy project to study, investigate, and try to play with dependency injection.

SYNOPSIS
========

Low level
---------

```raku
use Test;
use Deps;
my Deps $deps .= new;

$deps.register: Bla;
$deps.register: -> Int $a, Int :$b --> Str { "$a - $b" }, :name<value>;
$deps.register: 13;
$deps.register: 42, :name<a>;

is-deeply $deps.get(Bla),           Bla.new(value => "42 - 13", a => 42, b => 13);
is-deeply $deps.get(Int, :name<a>), 42                                           ;
is-deeply $deps.get(Int, :name<b>), Nil                                          ;
is-deeply $deps.get(Int),           13                                           ;
is-deeply $deps.get(Cool),          "42 - 13"                                    ;
```

By block
--------

```raku
use Test;
use Deps;

class C         { has Int $.attr = 42                }
class C1        { has $.attr                         }
role R          { has C1 $.a                         }
class C2 does R { has Int $.int = 42                 }
class C3 does R {                                    }
class C4 is C   { has C1 $.a; has C2 $.b; has C3 $.c }
class C5 is C4  {                                    }
class Bla {
   has $.value;
   has Int $.a;
   has Int $.b
}

my $old-deps = deps { injectable C, :name<class> }
deps {
   injectable C.new: :13attr;
   import-deps $old-deps;
   injected my C $obj;
   is-deeply $obj, C.new: :13attr;

   injected my C $class;
   is-deeply $class, C.new;
}

given Deps.new {
   .register: C1.new: :attr<value1>;
   .register: C2;
   .register: C3;
   .register: C4;
   .register: C5;

   is-deeply .get(C1), C1.new(attr => "value1");
   is-deeply .get(R) , C2.new(int => 42, a => C1.new(attr => "value1"));
   is-deeply .get(C2), C2.new(int => 42, a => C1.new(attr => "value1"));
   is-deeply .get(C3), C3.new(a => C1.new(attr => "value1"));
   is-deeply .get(C) , C4.new(
	   a => C1.new(attr => "value1"),
	   b => C2.new(
		   int => 42,
		   a => C1.new(attr => "value1")
	   ),
	   c => C3.new(
		   a => C1.new(attr => "value1")
	   )
   );
   is-deeply .get(C5), C5.new(
	   a => C1.new(attr => "value1"),
	   b => C2.new(
		   int => 42,
		   a => C1.new(attr => "value1")
	   ),
	   c => C3.new(
		   a => C1.new(attr => "value1")
	   )
   );
}
```

By function
-----------

```raku
use Test;
use Deps;

class UserIdStorage { has Int $.user-id }

sub do-background-stuff(UserIdStorage $storage? is copy) is injected {
   start { $storage.user-id * 2 }
}

sub handle-request(UInt $user-id) is injected {
   injectable UserIdStorage.new: :$user-id;
   do-background-stuff
}

is await(handle-request(21)), 42;
```

Instantiate injecting data
--------------------------

```raku
use Test;
use Deps;

class Example {
	has Int $.user-id;
	has Int $.int;
	has Str $.str;
}

deps {
   injectable 13;
   injectable 42, :name<user-id>;

   is-deeply instantiate(Example, :str<bla>), Example.new(user-id => 42, int => 13, str => "bla");
}
```

DESCRIPTION
===========

Deps is a toy project to test, play, investigate about dependency injection.

AUTHOR
======

Fernando Corrêa de Oliveira <fco@cpan.org>

COPYRIGHT AND LICENSE
=====================

Copyright 2025 Fernando Corrêa de Oliveira

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.


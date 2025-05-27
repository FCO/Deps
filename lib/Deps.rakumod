unit class Deps;

sub injected(Mu $var is rw, |c) is export { $var = $*DEPS.get($var, :name($var.VAR.name.substr: 1)) // $*DEPS.get: $var }
sub injectable(|c) is export { $*DEPS.register: |c }
sub import-deps($new-parent) is export { $*DEPS.import: $new-parent }
sub deps(&block, ::?CLASS $deps = $*DEPS.defined ?? $*DEPS.push-layer !! ::?CLASS.new) is export {
	{
		my $*DEPS = $deps;
		block
	}
	$deps
}

has ::?CLASS $.parent;
has %.factories;

method TWEAK(|) {
	$.register: self;
	$.register: self, :name<deps>;
}

method import(::?CLASS:D $new-parent) {
	return $!parent = $new-parent without $!parent;
	$!parent.import: $new-parent

}

method store(::Type, %hash (:$name, :&func)) {
	for Type.^mro.kv -> UInt $i, ::Type {
		%!factories{Type.^name}[$i].push: %hash;
		for 0 .. $i -> $j {
			$_ = [] without %!factories{Type.^name}[$j];
		}
	}
	for Type.^roles -> ::Type {
		%!factories{Type.^name}[1].push: %hash;
		$_ = [] without %!factories{Type.^name}[0];
	}
}

multi prepare-args(Any:U ::Type, ::?CLASS $deps --> Map()) {
	do for Type.^attributes -> Attribute $attr {
		my $type = $attr.type;
		my $name = $attr.name.substr: 2;
		my $value = $deps.get($type, :$name) // $deps.get: $type;
		$name => $_ with $value
	}
}

multi prepare-args(&func, ::?CLASS $deps --> Capture()) {
	do for &func.signature.params -> Parameter $par {
		my $type = $par.type;
		do if $par.named {
			my @names = $par.named_names;
			my $name  = @names.tail;
			my $value = $deps.get($type, :name(@names.any)) // $deps.get: $type;
			$name => $_ with $value
		} else {
			my $name = $par.name.substr: 1;
			my $value = $deps.get($type, :$name) // $deps.get: $type;
			$_ with $value
		}
	}
}

multi trait_mod:<is>(Sub $func, :$injected) is export {
	$func.wrap: sub (:$deps? = $*DEPS.defined ?? $*DEPS.push-layer !! Deps.new, |c) {
		{
			my $data = prepare-args $func, $deps;
			my $*DEPS = $deps;
			nextwith |$data, |c
		}
	}
}

multi method register(&function, :$lifecycle where { !.defined || $_ eq "stored" }, :$name) {
	my %hash = func => -> |c {
		my Capture $c = prepare-args &function, self;
		$ //= function |$c, |c
	}, |(:$name with $name);
	$.store: &function.returns, %hash;
}

multi method register(&function, :$lifecycle where { $_ eq "new" }, :$name) {
	my %hash = func => -> |c {
		say "new";
		my Capture $c = prepare-args &function, self;
		function |$c, |c
	}, |(:$name with $name);
	$.store: &function.returns, %hash;
}

multi method register(Any:D $obj, :$lifecycle where { !.defined || $_ eq "stored" }, :$name) {
	my %hash = func => -> | { $obj }, |(:$name with $name);
	$.store: $obj, %hash
}

multi method register(Any:U ::Type, :$lifecycle where { !.defined || $_ eq "stored" }, :$name) {
	my Type $obj;
	my %hash = func => -> |c {
		$ //= Type.new: |prepare-args(Type, self), |c
	}, |(:$name with $name);
	$.store: Type, %hash
}

multi method register(Any:U ::Type, :$lifecycle where { $_ eq "new" }, :$name) {
	my %hash = func => -> |c {
		Type.new: |prepare-args(Type, self), |c
	}, |(:$name with $name);
	$.store: Type, %hash
}

multi method register(Any:D $obj, :$lifecycle where { $_ eq "new" }) {
	my %hash = func => -> |c { $obj.WHAT.new: |c };
	$.store: $obj, %hash
}

method chain(Mu ::Type) {
	.take with %!factories{Type.^name};
	.chain: Type with $!parent;
}

method factory-to(Mu ::Type) {
	my @chain = lazy gather { $.chain: Type };
	lazy gather for 0 .. * -> $i {
		my $entered = 0;
		for @chain -> @elo {
			next unless @elo[$i]:exists;
			$entered++;
			.take for @elo[$i]<>;
		}
		last unless $entered
	}
}

method push-layer {
	my $new = ::?CLASS.new: :parent(self);
	$new
}

method pop-layer { $!parent }

multi method get(Mu ::Type, Str :$name!, |c) {
	for |$.factory-to: Type {
		next unless $_ ~~ Associative && (.<func>:exists);
		next unless (.<name>:exists) && .<name> eq $name;
		return .<func>(|c) # TODO: It needs to receive parameters
	}
}

multi method get(Mu ::Type, |c) {
	for |$.factory-to: Type {
		next unless $_ ~~ Associative && (.<func>:exists);
		return .<func>(|c) # TODO: It needs to receive parameters
	}
}

=begin pod

=head1 NAME

Deps - a toy project to study, investigate, and try to play with dependency injection.

=head1 SYNOPSIS

=head2 Low level

=begin code :lang<raku>

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

=end code

=head2 By block

=begin code :lang<raku>

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

   say injected my C $class;
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

=end code

=head2 By function

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

Deps is a toy project to test, play, investigate about dependency injection.

=head1 AUTHOR

Fernando Corrêa de Oliveira <fco@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Fernando Corrêa de Oliveira

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

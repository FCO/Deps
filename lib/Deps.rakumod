use Deps::LifeCycle;
use Deps::Item;
use Deps::Priority;
use Deps::Item::New;
use Deps::Item::Store;
use Deps::Item::Scope;
use Deps::Module;

class Deps {
	has ::?CLASS $.parent;
	has %.factories;
	has %.cache;
	has %.named-cache;

	method TWEAK(|) {
		$.register: self;
		$.register: self, :name<deps>;
	}

	multi method import(::?CLASS:D $new-parent) {
		return $!parent = $new-parent without $!parent;
		$!parent.import: $new-parent
	}

	multi method lifecycle-map(Store) { Deps::Item::Store }
	multi method lifecycle-map(New)   { Deps::Item::New   }
	multi method lifecycle-map(Scope) { Deps::Item::Scope }

	multi method new-item(
		Mu:U :$orig-type,
		Str() :$name,
		:&func,
		Mu :$value,
		Deps::LifeCycle :$lifecycle,
		Deps::Priority :$priority,
		:&only-if,
	) {
		$.lifecycle-map($lifecycle).new:
			:$orig-type,
			:$value,
			|(:$name with $name),
			|(:&func with &func),
			|(:$priority with $priority),
			:&only-if,
			:scope(self)
		;
	}

	method store(::Type, $item) {
		for Type.^mro.kv -> UInt $i, ::Type {
			last if Type.^name eq Any.^name;
			if $item.has-name && %!named-cache{Type.^name} {
				my \deleted = %!named-cache{Type.^name}:delete;
			}
			%!cache{Type.^name}:delete;
			%!factories{Type.^name}[$i].push: $item;
			for 0 .. $i -> $j {
				$_ = [] without %!factories{Type.^name}[$j];
			}
		}
		for Type.^roles -> ::Type {
			%!factories{Type.^name}[1].push: $item;
			$_ = [] without %!factories{Type.^name}[0];
		}
		$item.value
	}

	method instantiate(::Type, |c) {
		my %data = prepare-args Type, self;
		Type.new: |%data, |c
	}

	multi method register(
		::Type Any,
		:$name,
		Str() :$priority! where { Deps::Priority::{$priority.lc.tc} eq Unique },
	) {
		die "Deps already has a entry to {Type.^name}{" and name '$_'" with $name}" if $.get: Type, |(:$name with $name)
	}

	multi method register(
		&function,
		Str() :$lifecycle where { Deps::LifeCycle::{$lifecycle.lc.tc}:exists } = "Store",
		:$name,
		Str() :$priority where { Deps::Priority::{$priority.lc.tc}:exists } = "Strict",
		:&only-if,
		Capture :$capture
	) {
		my $orig-type = &function.returns;
		my Deps::Item $item = $.new-item:
			:$orig-type,
			func => -> |c {
				my Capture $c = prepare-args &function, self;
				function |$c, |($_ with $capture)
			},
			|(:$name with $name),
			:lifecycle(Deps::LifeCycle::{$lifecycle.lc.tc}),
			:priority(Deps::Priority::{$priority.lc.tc}),
			|(:&only-if with &only-if),
		;
		$.store: $orig-type, $item;
	}

	multi method register(
		Any:D $value,
		:$lifecycle where { Deps::LifeCycle::{$lifecycle.lc.tc}:exists } = "Store",
		:$name,
		Str() :$priority where { Deps::Priority::{$priority.lc.tc}:exists } = "Strict",
		:&only-if,
	) {
		my Deps::Item $item = $.new-item:
			:orig-type($value.WHAT),
			:$value,
			|(:$name with $name),
			:lifecycle(Deps::LifeCycle::{$lifecycle.lc.tc}),
			:priority(Deps::Priority::{$priority.lc.tc}),
			|(:&only-if with &only-if),
		;
		$.store: $value, $item
	}

	multi method register(
		Any:U ::Type,
		:$lifecycle where { Deps::LifeCycle::{$lifecycle.lc.tc}:exists } = "Store",
		:$name,
		Str() :$priority where { Deps::Priority::{$priority.lc.tc}:exists } = "Strict",
		:&only-if,
		Capture :$capture
	) {
		my Deps::Item $item = $.new-item:
			:orig-type(Type),
			func => -> |c {
				my %args = prepare-args(Type, self);
				Type.new: |%args, :$capture
			},
			|(:$name with $name),
			:lifecycle(Deps::LifeCycle::{$lifecycle.lc.tc}),
			:priority(Deps::Priority::{$priority.lc.tc}),
			|(:&only-if with &only-if),
		;
		$.store: Type, $item
	}

	multi method register(Bool :$only-if where *.not, |) {}
	multi method register(Bool :$only-if where *.so, |c) {
		$.register: |c
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

	multi method get(::Type, Str :$maybe-name!, Capture :$capture, Bool :$instantiate = True) {
		$.get(Type, :name($maybe-name), |(:$capture with $capture), :!instantiate)
		// $.get(Type, |(:$capture with $capture), :$instantiate)
		// Type
	}

	multi method get(::Type, Str :$name, Capture :$capture, Bool :$instantiate = False) {
		if $name.defined {
			return .get-value: self, :$capture with %!named-cache{Type.^name}{$name};
		} else {
			return .get-value: self, :$capture with %!cache{Type.^name};
		}

		my $previous-next;

		for |$.factory-to: Type {
			next unless .if;
			if $name.defined {
				next unless .has-name: $name;
				%!named-cache{Type.^name}{$name} = $_;
			} else {
				%!cache{Type.^name} = $_;
			}
			if .priority ~~ Defer {
				$previous-next = $_;
			} else {
				return .get-value: self, :$capture
			}
		}
		return .get-value: self, :$capture with $previous-next;
		try return $.instantiate(Type) if $instantiate;
		Type
	}
}

multi prepare-args(Any:U ::Type, Deps $deps --> Map()) {
	do for Type.^attributes -> Attribute $attr {
		my $type = $attr.type;
		my $maybe-name = $attr.name.substr: 2;
		my $value = $deps.get: $type, :$maybe-name;
		$maybe-name => $_ with $value
	}
}

multi prepare-args(&func, Deps $deps --> Capture()) {
	my @params = &func.signature.params;
	my @injected = @params.grep: *.?is-injected;
	@injected = @params unless @injected;

	my Capture() $c = do for @injected -> Parameter $par {
		my $type = $par.type;
		do if $par.named {
			my @names = $par.named_names;
			my $name  = @names.tail;
			my $value = $deps.get: $type, :maybe-name(@names.any);
			$name => $_ with $value
		} else {
			my $maybe-name = $par.name.substr: 1;
			my $value = $deps.get: $type, :$maybe-name;
			$_ with $value
		}
	}

	unless &func.?should-not-valudate-injected-params {
		for @injected -> $p {
			if $p.named {
				die "{ $p.name } was not provided by Deps" without $c.hash{$p.named_names.tail}
			} else {
				die "{ $p.name } was not provided by Deps" if $c.list < @injected.grep: !*.named
			}
		}
	}

	$c
}

multi trait_mod:<is>(Parameter $p, :$injected) is export {
	my $f = $p.^attributes.first: *.name eq q"$!flags";
	my $flags = $f.get_value: $p;
	$flags +|= nqp::const::SIG_ELEM_IS_OPTIONAL;
	$f.set_value: $p, $flags;
	role Injected { method is-injected { True } }

	$p does Injected
}

multi trait_mod:<is>(Sub $func, :$injected) is export {
	without $func.signature.params.first: *.?is-injected {
		trait_mod:<is> $_, :injected for $func.signature.params;
		$func does role { method should-not-valudate-injected-params { True } }
	}
	$func.wrap: sub (:$deps? = $*DEPS.defined ?? $*DEPS.push-layer !! Deps.new, |c) {
		my &orig = nextcallee;
		{
			my $data = prepare-args &orig, $deps;
			my $*DEPS = $deps;
			orig |$data, |c
		}
	}
}

sub EXPORT(--> Map()) {
	use Deps::Funcs;

	'&injected'    => -> |c { injected    |c, :class(Deps) },
	'&injectable'  => -> |c { injectable  |c, :class(Deps) },
	'&instantiate' => -> |c { instantiate |c, :class(Deps) },
	'&import-deps' => -> |c { import-deps |c, :class(Deps) },
	'&deps-root'   => -> |c { deps-root   |c, :class(Deps) },
	'&deps-scope'  => -> |c { deps-scope  |c, :class(Deps) },
	'&deps'        => -> |c { deps        |c, :class(Deps) },
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

=head2 Instantiate injecting data

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

Deps is a toy project to test, play, investigate about dependency injection.

=head1 AUTHOR

Fernando Corrêa de Oliveira <fco@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Fernando Corrêa de Oliveira

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

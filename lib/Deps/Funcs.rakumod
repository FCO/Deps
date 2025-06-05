multi set-deps($deps is rw, $DEPS) {
	$deps = $DEPS if not $deps.defined;
}
multi set-deps($, $) {}

sub get-deps($deps, Any:U :$class) {
	return $deps if $deps ~~ $class;
	with $deps {
		die "It should be a Str od a Deps object" unless $deps ~~ Str;
		return .{$deps} with %*DEPS;
		die "Scope $deps not found"
	}
	$*DEPS
}

multi injected(Mu $var is rw, :$deps, :$class, |c) is export {
	my $deps-obj = get-deps($deps, :$class);
	$var = $deps-obj.get($var, |(:$deps with $deps), :name($var.VAR.name.substr: 1)) // $deps-obj.get: $var
}
multi injected(Mu $var, :$deps, :$class, |c) is export {
	my $deps-obj = get-deps($deps, :$class);
	$deps-obj.get($var, :deps($var.VAR.name.substr: 1)) // $deps-obj.get: $var
}
sub injectable(:$deps, :$class, |c) is export { get-deps($deps, :$class).register: |c }
sub instantiate(:$deps, :$class, |c) is export { get-deps($deps, :$class).instantiate: |c }

sub import-deps($new-parent, :$deps, :$class) is export {
	get-deps($deps, :$class).import: $new-parent
}

sub deps-base($deps-obj, &block, :$deps is raw) {
	my %named-deps = |$_ with %*DEPS;
	{
		my %*DEPS = %named-deps;
		my $*DEPS = $deps-obj;
		set-deps $deps, $deps-obj;
		%*DEPS{$_} = $deps-obj with $deps;
		block |($deps-obj if &block.arity);
		$deps-obj
	}
}

multi deps-root( &block, :$deps is raw, Any:U :$class, |c ) is export {
	my $deps-obj = $class.new;
	deps-base $deps-obj, &block, :$deps, |c
}

sub deps-scope(
	&block,
	:$deps is raw,
	:$parent = ($*DEPS // die "deps-scope must be used inside a scope"),
	:$class,
	|c
) is export {
	my $deps-obj = $parent.push-layer;
	deps-base $deps-obj, &block, :$deps, |c
}
sub deps(|c) is export {
	do if $*DEPS {
		deps-scope |c
	} else {
		deps-root |c
	}
}



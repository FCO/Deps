use Deps::Item;
use Deps::LifeCycle;
unit class Deps::Item::New does Deps::Item;

has Deps::LifeCycle $.lifecycle = New;

submethod TWEAK(|) {
	die "New lifecycle needs a function!" without &!func;
}

method get-value($scope, Capture :$capture) {
	&.func.($.scope, |(|$_ with $capture));
}

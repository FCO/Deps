use Deps::Item;
use Deps::LifeCycle;
unit class Deps::Item::Store does Deps::Item;

has Deps::LifeCycle $.lifecycle = Store;

method get-value($scope, Capture :$capture) {
	return $.value if $.created;
	
	$.value = &.func.($.scope, |(|$_ with $capture));
	$.created = True;
	$.value
}

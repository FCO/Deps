use Deps::Item;
use Deps::LifeCycle;
unit class Deps::Item::Scope does Deps::Item;

has Deps::LifeCycle $.lifecycle = Scope;

method get-value($scope, Capture :$capture) {
	if $scope !=== $.scope {
		my $clone = self.clone: :value(Nil), :created(False), :$scope;
		$scope.store: $!orig-type, $clone;
		return $clone.get-value: $scope
	}
	return $.value if $.created;
	
	$.value = &.func.($.scope, |(|$_ with $capture));
	$.created = True;
	$.value
}

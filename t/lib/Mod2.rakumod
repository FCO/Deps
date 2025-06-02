use Deps;

sub mod2(Deps $deps) is export {
	$deps.register: 42;
	$deps.register: 13, :name<int-with-name>
}

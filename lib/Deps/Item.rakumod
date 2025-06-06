use Deps::Priority;
unit role Deps::Item;

has Mu:U           $.orig-type;
has Str()          $.name;
has Mu             $.value   is rw;
has Bool           $.created is rw = False;
has                &.func;
has                $.scope   is required;
has Deps::Priority $.priority = Strict;

method gist {
	"Item[{$.lifecycle}].new:\n\tname => {$!name.raku},\n\tpriority => {$!priority.Str}\n\tfunc => {&!func.raku}\n\tvalue => {$!value.raku.substr: 0, 50},\n\tcreated => {$!created}"
}

submethod TWEAK(Mu :$value, |) { $!created = $value.defined }
method get-value($scope)       { ... }

method has-name(Str() $name?) {
	$!name.defined && (!$name.defined || $name eq $!name)
}

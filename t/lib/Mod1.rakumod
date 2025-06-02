use Deps;

sub mod1 is export {
	injectable "this was added by importing a module";
	injectable "this was added by importing a module and has a name", :name<str-with-name>
}

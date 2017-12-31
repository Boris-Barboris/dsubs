module dsubs_common.app;

version ( unittest )
{
	import std.stdio;

	int main(string[] argv)
	{
		writeln("This is dsubs_common library");
		writeln("Unit-tests went ok!");
		return 0;
	}

}

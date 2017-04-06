import std.stdio;

import threading.taskgraph: test_graph_runner;

int main(string[] argv)
{
    writeln("This is dsubs_common library");
	writeln("Unit-tests went ok!");

	test_graph_runner();
    return 0;
}

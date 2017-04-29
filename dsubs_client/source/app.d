module dsubs_client.app;

import std.experimental.logger;

import dsubs_client.tests;


int main(string[] argv)
{
	info("Unit tests OK");
	test_div_render();
	return 0;
}

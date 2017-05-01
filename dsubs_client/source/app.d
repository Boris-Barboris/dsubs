module dsubs_client.app;

import std.experimental.logger;

import dsubs_client.tests;


int main(string[] argv)
{
	info("Unit tests OK");
	test_menu_routing();
	return 0;
}

module dsubs_server.tests.steering;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;


unittest
{
	Globals.buildForTests();
	SpawnReq req = SpawnReq("Stork", "Five-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.targetThrottle = 1.0f;
	s.targetCourse = dgr2rad(-90);
	s.register();
	info("sub started at position ", s.transform.position);
	Globals.sim.worldTimeLimit = 45 * cast(ulong)1e6;
	Globals.sim.start();
	Globals.sim.join();
	info("sub finished at position ", s.transform.position);
	Globals.resetForTests();
}
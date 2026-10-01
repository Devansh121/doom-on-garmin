import Toybox.Lang;
import Toybox.Test;

(:test)
function testSpawnAndRemoveMobj(logger as Test.Logger) as Boolean {
    initRender();
    Info.Info_Init();
    loadE1M1();

    var x = 1056 << 16;
    var y = -3616 << 16;
    var mo = PMobj.P_SpawnMobj(x, y, PMobj.ONFLOORZ, Info.MT_TROOP);
    var ss = RMain.R_PointInSubsector(x, y);
    var sec = PSetup.subsectors_sector[ss];

    Test.assertEqual(PMobj.mobjs_subsector[mo], ss);
    Test.assertEqual(PMobj.mobjs_z[mo], PSetup.sectors_floorheight[sec]);
    Test.assertEqual(PMobj.mobjs_health[mo], 60);
    Test.assertEqual(PSetup.sectors_thinglist[sec], mo);
    Test.assertEqual(PTick.thinkers_next[PTick.thinkers_prev[0]], 0);
    Test.assertEqual(PTick.thinkers_prev[0], mo);

    // a second one goes on the front of the sector list
    var mo2 = PMobj.P_SpawnMobj(x, y, PMobj.ONFLOORZ, Info.MT_POSSESSED);
    Test.assertEqual(PSetup.sectors_thinglist[sec], mo2);
    Test.assertEqual(PMobj.mobjs_snext[mo2], mo);

    PMobj.P_RemoveMobj(mo2);
    Test.assertEqual(PSetup.sectors_thinglist[sec], mo);
    Test.assertEqual(PTick.thinkers_function[mo2], PTick.TF_REMOVED);

    // the removed thinker is freed when its turn comes
    var free = PTick.numfree;
    PTick.P_RunThinkers();
    while (!PTick.P_RunThinkersStep(16)) {
    }
    Test.assertEqual(PTick.numfree, free + 1);
    Test.assertEqual(PTick.thinkers_prev[0], mo);
    return true;
}

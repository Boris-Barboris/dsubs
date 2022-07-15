ALTER TABLE simulator_instances DROP FOREIGN KEY simulator_instances_ibfk_1;

DROP TABLE simulator_destroy_reasons;

UPDATE scenario_types SET scenario_types.name = "campaignMission"
    WHERE scenario_types.name = "capmaignMission";

UPDATE db_revision SET revision = '2';
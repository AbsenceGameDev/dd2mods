--[[ @author: https://github.com/AbsenceGameDev. Nemes!5: Toil & Trouble - Definitions
  - Constants shared by submodules.
  - Names written in CAPITALS are for unconfirmed behaviours.
]]

local Definitions = {};

--
-- Names and paths
Definitions.DisplayName   = "Nemes!5: Toil & Trouble";
Definitions.ModVersion    = "0.1.0";
Definitions.DataDirectory = "Nemes5/"; -- under reframework/data
Definitions.SettingsPath  = "Nemes5/config.json";
Definitions.ProbeLogPath  = "Nemes5/probe_events.json";
Definitions.ProbeEventLimit = 200;

--
-- Systems, in the order the panel lists them.
Definitions.Systems = { "World", "Factions", "Officers", "Ghost", "Captives" };

--
-- Engine points checked at startup per system: types, methods, system hooks, fields.
-- Methods are "name(parameter types)" for overloaded or hooked methods, or "name" alone where the parameters hold generic types.
Definitions.EnginePoints = {
  { System = "World", Type = "app.TimeManager",
    Methods = { "get_InGameDay()", "get_InGameElapsedDaySeconds()", "get_WholePlayTime()", "setTime(System.Int32, System.Int32, System.Int32, System.Boolean)",
                "setTimeScale(System.Single)", "addTimeZoneChangeCallBack" },
    Fields = { "InGameDaySeconds" } },
  { System = "World", Type = "app.SaveDataManager",
    Methods = { "getLoadingGameSlotId()", "requestSaveSlot(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])",
                "requestLoadSlot(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])" } },
  { System = "World", Type = "app.GuiManager", Methods = { "loadGameSaveData(app.SaveDataBase)", "saveGameSaveData()", "makeLoopSaveData()" } },

  { System = "Factions", Type = "app.GenerateManager",
    Methods = { "getPoolGenerateInfoContainerForCharacter", "forceRequestCreateInstance",
                "registerDisableZoneSphere", "registerDisableZoneCylinder", "registerDisableDestroyRequestID(app.CharacterID)",
                "getDestroyRangeXZSq(app.GeneratorCategory, app.LoadAreaEnum, System.Boolean, System.Boolean)", "getDestroyWideRangeXZSq()",
                "getReGenerateDistance(app.GeneratorCategory, app.LoadAreaEnum, System.Boolean)",
                "getAliveCharaRepopTime(System.Boolean, System.Boolean)", "getDeadCharaRepopTime(System.Boolean, System.Boolean)",
                "isNeverGenerate(app.UniqueID)", "isNeverGenerateByDead(app.UniqueID)", "cancelNeverGenerateByDead(app.UniqueID)",
                "getGenerateLimit(app.GeneratorCategory)", "getGenerateRuleLimit(app.GeneratorCategory)",
                "getExecInstantiateUpperLimit(app.GeneratorCategory)", "isOverGenerateLimit(app.GeneratorCategory)",
                "convContainerToRequestSaveData", "getEnemyRequests" },
    Fields = { "RequestGenerateTimingHandler", "InstantiatedBeginTimingHandler", "FixDestroyCharacterTimingHandler", "CancelRequestTimingHandler" } },
  { System = "Factions", Type = "app.RePopManager",
    Methods = { "registCharaRepopTimer", "unregistCharaRepopTimer(app.GeneratorCategory, app.UniqueID, System.Boolean)", "resetAllTime()" } },
  { System = "Factions", Type = "app.BattleRelationshipHolder",
    Methods = { "requestSetBidirectionalRelationship(System.UInt32, System.UInt32, app.Character.BattleRelationship)",
                "requestSetRelationshipFromTo(System.UInt32, System.UInt32, app.Character.BattleRelationship)",
                "setBidirectionalRelationship(System.UInt32, System.UInt32, app.Character.BattleRelationship)" } },
  { System = "Factions", Type = "app.CharacterGroupContext", Methods = { "setTempGroup(System.String)" } },

  { System = "Officers", Type = "app.Character",
    Methods = { "onDieFromAttack(app.HitController.DamageInfo)", "isKilledByCharacter(app.HitController.DamageInfo)", "get_IsDead()" } },
  { System = "Officers", Type = "app.CharacterManager", Methods = { "get_IsManualPlayerDead()" } },

  { System = "Ghost", Type = "app.CharacterManager", Methods = { "get_WakestoneUser()" } },
  { System = "Ghost", Type = "app.WakestoneUser",
    Methods = { "requestUseWakestoneToRevivePlayer(app.WakestoneUser.UseItemEnum)", "cancelUseWakestone()", "get_IsConfirmToRevivePlayer()",
                "isEnableUseRealWakestone()", "isEnableUseWakestoneIncludingForgery()" } },
  { System = "Ghost", Type = "app.ReviveFromWakestone", Methods = { "revive(app.Character, System.Single, System.Boolean)", "reviveIfNeeded()" } },
  { System = "Ghost", Type = "app.Human", Methods = { "notifyReviveFromWakestone()" } },
  { System = "Ghost", Type = "app.Character.QuestFlag", Fields = { "DisableReviveFromWakestone" } },

  { System = "Captives", Type = "app.CatchController" },
  { System = "Captives", Type = "app.CaughtController" },
  { System = "Captives", Type = "app.CrimeManager.IncarcerationStates" },
  { System = "Captives", Type = "app.HumanEnemyManager.ArrestRoutine" },
  { System = "Captives", Type = "app.actinter.cmd.GuardCatch" },
  { System = "Captives", Type = "app.TalkEventManager",
    Methods = { "addPlayRequest", "canPlay(app.TalkEventDefine.ID)", "addChoice(System.Guid)" } },
  { System = "Captives", Type = "app.TalkManager", Methods = { "getHumanEnemySituationMsgs" } },
  { System = "Captives", Type = "app.TalkCameraController" },
  { System = "Captives", Type = "app.TalkInteractController" },
};

--
-- Settings
Definitions.SettingsDefaults = {
  bEnabled = true, -- Disables mod functionality
};

return Definitions;

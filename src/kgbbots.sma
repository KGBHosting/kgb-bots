#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>

#pragma semicolon 1

#define PLUGIN_NAME "KGB Bots"
#define PLUGIN_VERSION "2.5"
#define PLUGIN_AUTHOR "KGB Hosting"

#define DEFAULT_STATIC_BOTS 2
#define MAX_MANAGED_BOTS 8
#define BOT_NAME_BUFFER 35
#define REASON_BUFFER 128
#define LOG_BUFFER 192
#define CONFIG_FILE_NAME "kgbbots.cfg"

#define TASK_ENABLE_PERIODIC_CHECK 10001
#define TASK_REPEATING_CHECK 10002
#define TASK_DELAYED_CHECK 10003
#define TASK_ADD_BOT 10004

enum
{
	Cvar_BotName1,
	Cvar_BotName2,
	Cvar_MinPlayers,
	Cvar_StartTime,
	Cvar_EndTime,
	Cvar_OneCondition,
	Cvar_OneBot,
	Cvar_NoRounds,
	Cvar_MaxBots,
	Cvar_FillPlayers,
	Cvar_GracePeriod,
	Cvar_Count
};

new const g_CvarNames[Cvar_Count][] =
{
	"amx_botname",
	"amx_botname2",
	"amx_minplayers",
	"amx_starttime",
	"amx_endtime",
	"amx_onecon",
	"amx_onebot",
	"amx_norounds",
	"amx_maxbots",
	"amx_fillplayers",
	"amx_graceperiod"
};

new const g_CvarDefaults[Cvar_Count][] =
{
	"KGB Bot1",
	"KGB Bot2",
	"10",
	"0",
	"12",
	"0",
	"0",
	"0",
	"2",
	"0",
	"0"
};

new g_CvarPointer[Cvar_Count];
new g_MaxPlayers;
new g_BotUserIds[MAX_MANAGED_BOTS];
new bool:g_BotKickPending[MAX_MANAGED_BOTS];
new g_BotCount;
new g_ConfigPath[128];
new bool:g_IsFirstRound = true;
new g_RemoveGraceTarget = -1;
new Float:g_RemoveGraceStartedAt;
new bool:g_CapacityWasFull;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar("kgbbots", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY);

	register_logevent("Event_RoundEnd", 2, "1=Round_End");
	register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");

	register_concmd("amx_kgbbots_status", "ConCmdKgbBotsStatus", ADMIN_CFG, "- shows current KGB Bots state");
	register_concmd("amx_kgbbots_reload", "ConCmdKgbBotsReload", ADMIN_CFG, "- reloads kgbbots.cfg and checks bot state");

	for (new i = 0; i < Cvar_Count; i++)
	{
		g_CvarPointer[i] = register_cvar(g_CvarNames[i], g_CvarDefaults[i]);
	}

	g_MaxPlayers = get_maxplayers();
}

public plugin_cfg()
{
	BuildConfigPath();
	EnsureDefaultConfig();
	ExecuteConfig();

	set_task(3.0, "Task_EnablePeriodicChecks", TASK_ENABLE_PERIODIC_CHECK);
}

public Event_RoundEnd()
{
	if (!g_IsFirstRound)
	{
		return;
	}

	g_IsFirstRound = false;
}

public Event_NewRound()
{
	if (g_IsFirstRound)
	{
		return;
	}

	CheckConditions();
}

public client_putinserver(id)
{
	if (ShouldCheckOnPlayerChange())
	{
		ScheduleDelayedCheck();
	}
}

#if AMXX_VERSION_NUM >= 190
public client_disconnected(id, bool:drop, message[], maxlen)
#else
public client_disconnect(id)
#endif
{
	if (ShouldCheckOnPlayerChange())
	{
		ScheduleDelayedCheck();
	}
}

public ConCmdKgbBotsStatus(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED;
	}

	PrintStatus(id);
	return PLUGIN_HANDLED;
}

public ConCmdKgbBotsReload(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED;
	}

	ExecuteConfig();
	ClearRemovalGrace();
	g_CapacityWasFull = false;
	SyncPeriodicCheckTask();
	CheckConditions();
	PrintStatus(id);
	LogAdminCommand(id, "Config reloaded");

	return PLUGIN_HANDLED;
}

public Task_EnablePeriodicChecks(taskId)
{
	SyncPeriodicCheckTask();
	CheckConditions();
}

public Task_PeriodicCheck(taskId)
{
	CheckConditions();
}

public Task_DelayedCheck(taskId)
{
	CheckConditions();
}

public CheckConditions()
{
	RefreshManagedBots();

	new desiredBots;
	new reason[REASON_BUFFER];
	EvaluateDesiredBots(desiredBots, reason, charsmax(reason));

	if (desiredBots < g_BotCount)
	{
		if (HasPendingRemovalAboveTarget(desiredBots))
		{
			return;
		}

		if (!RemovalGraceSatisfied(desiredBots, reason))
		{
			return;
		}

		KickExtraBots(desiredBots, reason);
		ClearRemovalGrace();
		return;
	}

	ClearRemovalGrace();

	if (desiredBots > g_BotCount)
	{
		if (HasCapacityForMoreBot())
		{
			g_CapacityWasFull = false;
			ScheduleBotAdd();
			return;
		}

		if (!g_CapacityWasFull)
		{
			new logLine[LOG_BUFFER];
			formatex(logLine, charsmax(logLine), "Cannot add bot: server is full. current=%d desired=%d. %s", g_BotCount, desiredBots, reason);
			LogBotEvent(logLine);
			g_CapacityWasFull = true;
		}

		return;
	}

	g_CapacityWasFull = false;
}

public Task_AddBot(taskId)
{
	RefreshManagedBots();

	new desiredBots;
	new reason[REASON_BUFFER];
	EvaluateDesiredBots(desiredBots, reason, charsmax(reason));

	if (desiredBots <= g_BotCount)
	{
		return;
	}

	if (!HasCapacityForMoreBot())
	{
		if (!g_CapacityWasFull)
		{
			new capacityLog[LOG_BUFFER];
			formatex(capacityLog, charsmax(capacityLog), "Cannot add bot: server is full. current=%d desired=%d. %s", g_BotCount, desiredBots, reason);
			LogBotEvent(capacityLog);
			g_CapacityWasFull = true;
		}

		return;
	}

	new botSlot = g_BotCount;

	if (botSlot >= MAX_MANAGED_BOTS)
	{
		return;
	}

	new botName[BOT_NAME_BUFFER];
	GetBotName(botSlot, botName, charsmax(botName));

	new botId = engfunc(EngFunc_CreateFakeClient, botName);

	if (!botId)
	{
		new failureLog[LOG_BUFFER];
		formatex(failureLog, charsmax(failureLog), "Failed to create bot ^"%s^". current=%d desired=%d. %s", botName, g_BotCount, desiredBots, reason);
		LogBotEvent(failureLog);
		return;
	}

	dllfunc(MetaFunc_CallGameEntity, "player", botId);
	set_pev(botId, pev_flags, FL_FAKECLIENT);

	set_pev(botId, pev_model, "");
	set_pev(botId, pev_viewmodel2, "");
	set_pev(botId, pev_modelindex, 0);

	set_pev(botId, pev_renderfx, kRenderFxNone);
	set_pev(botId, pev_rendermode, kRenderTransAlpha);
	set_pev(botId, pev_renderamt, 0.0);

	set_pdata_int(botId, 114, 3);
	cs_set_user_team(botId, CS_TEAM_UNASSIGNED);

	new userid = get_user_userid(botId);
	g_BotUserIds[g_BotCount] = userid;
	g_BotKickPending[g_BotCount] = false;
	g_BotCount++;
	g_CapacityWasFull = false;

	new addLog[LOG_BUFFER];
	formatex(addLog, charsmax(addLog), "Added bot ^"%s^" (#%d). current=%d desired=%d. %s", botName, userid, g_BotCount, desiredBots, reason);
	LogBotEvent(addLog);

	if (g_BotCount < desiredBots)
	{
		set_task(1.3, "Task_AddBot", TASK_ADD_BOT);
	}
}

stock BuildConfigPath()
{
	new configsDir[96];
	get_configsdir(configsDir, charsmax(configsDir));
	formatex(g_ConfigPath, charsmax(g_ConfigPath), "%s/%s", configsDir, CONFIG_FILE_NAME);
}

stock EnsureDefaultConfig()
{
	if (file_exists(g_ConfigPath))
	{
		return;
	}

	write_file(g_ConfigPath, "// KGB Bots v2.5");
	write_file(g_ConfigPath, "// Generated automatically on first load. Existing config files are never overwritten.");
	write_file(g_ConfigPath, "// Hours use server local time, from 0 to 23. Same start/end means all day.");
	write_file(g_ConfigPath, "// Fake clients are invisible in-game but visible in server browser/query metadata.");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Name for the first managed bot.");
	write_file(g_ConfigPath, "amx_botname ^"KGB Bot1^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Name for the second managed bot. Extra dynamic bots use names like KGB Bot 3.");
	write_file(g_ConfigPath, "amx_botname2 ^"KGB Bot2^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Player-count rule. Enable bots when human players are at or below this value. Use 0 to ignore this rule.");
	write_file(g_ConfigPath, "amx_minplayers ^"10^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Start hour for the time rule, using server local time, from 0 to 23.");
	write_file(g_ConfigPath, "amx_starttime ^"0^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// End hour for the time rule. Same as start means all day. Example: 22 to 6 runs overnight.");
	write_file(g_ConfigPath, "amx_endtime ^"12^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Rule mode. 0 = time rule AND player-count rule. 1 = time rule OR player-count rule.");
	write_file(g_ConfigPath, "amx_onecon ^"0^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Static mode count. 1 = one bot. 0 = two bots. Ignored when amx_fillplayers is enabled.");
	write_file(g_ConfigPath, "amx_onebot ^"0^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Check mode. 0 = normal round-based checks. 1 = check every 30 seconds.");
	write_file(g_ConfigPath, "amx_norounds ^"0^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Safety cap for managed bots, from 0 to 8. Keep 2 for old behavior.");
	write_file(g_ConfigPath, "amx_maxbots ^"2^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Dynamic fill target. 0 = static mode. Above 0 fills visible population up to this target, capped by amx_maxbots.");
	write_file(g_ConfigPath, "amx_fillplayers ^"0^"");
	write_file(g_ConfigPath, "");
	write_file(g_ConfigPath, "// Removal delay in seconds after rules stop matching. 0 = remove immediately. Try 60 to smooth short player changes.");
	write_file(g_ConfigPath, "amx_graceperiod ^"0^"");
}

stock ExecuteConfig()
{
	server_cmd("exec ^"%s^"", g_ConfigPath);
	server_exec();
}

stock EvaluateDesiredBots(&desiredBots, reason[], reasonLen)
{
	new humanPlayers = GetHumanPlayerCount();
	new bool:timeOk = IsCurrentHourInWindow();
	new bool:playerCountOk = IsHumanPlayerCountBelowLimit(humanPlayers);

	if (!ActivationRulesMatch(timeOk, playerCountOk))
	{
		desiredBots = 0;
		FormatInactiveReason(reason, reasonLen, timeOk, playerCountOk);
		return;
	}

	desiredBots = GetDesiredBotCount(humanPlayers);
	FormatDesiredReason(reason, reasonLen, humanPlayers);
}

stock bool:ActivationRulesMatch(bool:timeOk, bool:playerCountOk)
{
	if (get_pcvar_num(g_CvarPointer[Cvar_OneCondition]))
	{
		return timeOk || playerCountOk;
	}

	return timeOk && playerCountOk;
}

stock FormatInactiveReason(reason[], reasonLen, bool:timeOk, bool:playerCountOk)
{
	if (get_pcvar_num(g_CvarPointer[Cvar_OneCondition]))
	{
		formatex(reason, reasonLen, "time and player-count rules failed");
		return;
	}

	if (!timeOk && !playerCountOk)
	{
		formatex(reason, reasonLen, "time and player-count rules failed");
		return;
	}

	if (!timeOk)
	{
		formatex(reason, reasonLen, "time rule failed");
		return;
	}

	formatex(reason, reasonLen, "player-count rule failed");
}

stock FormatDesiredReason(reason[], reasonLen, humanPlayers)
{
	new maxBots = GetConfiguredMaxBots();
	new fillTarget = GetFillTarget();

	if (maxBots <= 0)
	{
		formatex(reason, reasonLen, "max bots is 0");
		return;
	}

	if (fillTarget > 0)
	{
		formatex(reason, reasonLen, "fill target %d with %d human players, max bots %d", fillTarget, humanPlayers, maxBots);
		return;
	}

	formatex(reason, reasonLen, "%s mode, max bots %d", get_pcvar_num(g_CvarPointer[Cvar_OneBot]) ? "one-bot" : "two-bot", maxBots);
}

stock bool:IsCurrentHourInWindow()
{
	new currentHour, minutes, seconds;
	time(currentHour, minutes, seconds);

	new startHour = ClampHour(get_pcvar_num(g_CvarPointer[Cvar_StartTime]));
	new endHour = ClampHour(get_pcvar_num(g_CvarPointer[Cvar_EndTime]));

	if (startHour == endHour)
	{
		return true;
	}

	if (startHour < endHour)
	{
		return startHour <= currentHour && currentHour < endHour;
	}

	return currentHour >= startHour || currentHour < endHour;
}

stock bool:IsHumanPlayerCountBelowLimit(humanPlayers)
{
	new minPlayers = get_pcvar_num(g_CvarPointer[Cvar_MinPlayers]);

	if (minPlayers <= 0)
	{
		return true;
	}

	return humanPlayers <= minPlayers;
}

stock GetDesiredBotCount(humanPlayers)
{
	new maxBots = GetConfiguredMaxBots();

	if (maxBots <= 0)
	{
		return 0;
	}

	new fillTarget = GetFillTarget();

	if (fillTarget > 0)
	{
		new neededBots = fillTarget - humanPlayers;

		if (neededBots <= 0)
		{
			return 0;
		}

		return MinInt(neededBots, maxBots);
	}

	new desiredBots = get_pcvar_num(g_CvarPointer[Cvar_OneBot]) ? 1 : DEFAULT_STATIC_BOTS;
	return MinInt(desiredBots, maxBots);
}

stock GetConfiguredMaxBots()
{
	return ClampInt(get_pcvar_num(g_CvarPointer[Cvar_MaxBots]), 0, MAX_MANAGED_BOTS);
}

stock GetFillTarget()
{
	new fillTarget = get_pcvar_num(g_CvarPointer[Cvar_FillPlayers]);
	return fillTarget > 0 ? fillTarget : 0;
}

stock GetRemovalGraceSeconds()
{
	new gracePeriod = get_pcvar_num(g_CvarPointer[Cvar_GracePeriod]);
	return gracePeriod > 0 ? gracePeriod : 0;
}

stock GetHumanPlayerCount()
{
	new players[32], playerCount;
	get_players(players, playerCount, "ch");
	return playerCount;
}

stock bool:HasCapacityForMoreBot()
{
	return GetConnectedClientCount() < g_MaxPlayers;
}

stock GetConnectedClientCount()
{
	new connectedClients = 0;

	for (new id = 1; id <= g_MaxPlayers; id++)
	{
		if (is_user_connected(id))
		{
			connectedClients++;
		}
	}

	return connectedClients;
}

stock bool:RemovalGraceSatisfied(desiredBots, const reason[])
{
	new gracePeriod = GetRemovalGraceSeconds();

	if (gracePeriod <= 0)
	{
		return true;
	}

	new Float:now = get_gametime();

	if (g_RemoveGraceTarget != desiredBots || g_RemoveGraceStartedAt <= 0.0)
	{
		g_RemoveGraceTarget = desiredBots;
		g_RemoveGraceStartedAt = now;

		new graceLog[LOG_BUFFER];
		formatex(graceLog, charsmax(graceLog), "Removal grace started. current=%d target=%d grace=%d sec. %s", g_BotCount, desiredBots, gracePeriod, reason);
		LogBotEvent(graceLog);
		return false;
	}

	return now - g_RemoveGraceStartedAt >= float(gracePeriod);
}

stock GetRemovalGraceRemaining()
{
	if (g_RemoveGraceTarget < 0 || g_RemoveGraceStartedAt <= 0.0)
	{
		return 0;
	}

	new gracePeriod = GetRemovalGraceSeconds();
	new elapsed = floatround(get_gametime() - g_RemoveGraceStartedAt, floatround_floor);
	new remaining = gracePeriod - elapsed;

	return remaining > 0 ? remaining : 0;
}

stock ClearRemovalGrace()
{
	g_RemoveGraceTarget = -1;
	g_RemoveGraceStartedAt = 0.0;
}

stock bool:HasPendingRemovalAboveTarget(desiredBots)
{
	for (new i = desiredBots; i < g_BotCount; i++)
	{
		if (g_BotKickPending[i])
		{
			return true;
		}
	}

	return false;
}

stock RefreshManagedBots()
{
	new compactedUserIds[MAX_MANAGED_BOTS];
	new bool:compactedKickPending[MAX_MANAGED_BOTS];
	new compactedCount = 0;

	for (new i = 0; i < MAX_MANAGED_BOTS; i++)
	{
		if (!g_BotUserIds[i])
		{
			continue;
		}

		new client = FindClientByUserid(g_BotUserIds[i]);

		if (client && is_user_bot(client))
		{
			compactedUserIds[compactedCount] = g_BotUserIds[i];
			compactedKickPending[compactedCount] = g_BotKickPending[i];
			compactedCount++;
		}
	}

	for (new i = 0; i < MAX_MANAGED_BOTS; i++)
	{
		g_BotUserIds[i] = i < compactedCount ? compactedUserIds[i] : 0;
		g_BotKickPending[i] = i < compactedCount ? compactedKickPending[i] : false;
	}

	g_BotCount = compactedCount;
}

stock FindClientByUserid(userid)
{
	for (new id = 1; id <= g_MaxPlayers; id++)
	{
		if (is_user_connected(id) && get_user_userid(id) == userid)
		{
			return id;
		}
	}

	return 0;
}

stock KickExtraBots(desiredBots, const reason[])
{
	for (new i = g_BotCount - 1; i >= desiredBots; i--)
	{
		KickManagedBotAtSlot(i, desiredBots, reason);
	}
}

stock KickManagedBotAtSlot(slot, desiredBots, const reason[])
{
	if (slot < 0 || slot >= MAX_MANAGED_BOTS || !g_BotUserIds[slot] || g_BotKickPending[slot])
	{
		return;
	}

	new userid = g_BotUserIds[slot];
	new botName[BOT_NAME_BUFFER];
	GetManagedBotName(slot, botName, charsmax(botName));

	server_cmd("kick #%d", userid);
	g_BotKickPending[slot] = true;

	new removeLog[LOG_BUFFER];
	formatex(removeLog, charsmax(removeLog), "Removing bot ^"%s^" (#%d). current=%d target=%d. %s", botName, userid, g_BotCount, desiredBots, reason);
	LogBotEvent(removeLog);
}

stock ScheduleBotAdd()
{
	if (!task_exists(TASK_ADD_BOT))
	{
		set_task(1.5, "Task_AddBot", TASK_ADD_BOT);
	}
}

stock ScheduleDelayedCheck()
{
	if (!task_exists(TASK_DELAYED_CHECK))
	{
		set_task(2.0, "Task_DelayedCheck", TASK_DELAYED_CHECK);
	}
}

stock bool:ShouldCheckOnPlayerChange()
{
	return GetFillTarget() > 0;
}

stock SyncPeriodicCheckTask()
{
	if (get_pcvar_num(g_CvarPointer[Cvar_NoRounds]))
	{
		if (!task_exists(TASK_REPEATING_CHECK))
		{
			set_task(30.0, "Task_PeriodicCheck", TASK_REPEATING_CHECK, "", 0, "b");
		}

		return;
	}

	if (task_exists(TASK_REPEATING_CHECK))
	{
		remove_task(TASK_REPEATING_CHECK);
	}
}

stock PrintStatus(id)
{
	RefreshManagedBots();

	new desiredBots;
	new reason[REASON_BUFFER];
	EvaluateDesiredBots(desiredBots, reason, charsmax(reason));

	new humanPlayers = GetHumanPlayerCount();
	new connectedClients = GetConnectedClientCount();
	new bool:timeOk = IsCurrentHourInWindow();
	new bool:playerCountOk = IsHumanPlayerCountBelowLimit(humanPlayers);
	new bool:rulesOk = ActivationRulesMatch(timeOk, playerCountOk);

	console_print(id, "----- KGB Bots %s -----", PLUGIN_VERSION);
	console_print(id, "Config: %s", g_ConfigPath);
	console_print(id, "Bots: current=%d desired=%d max=%d fillplayers=%d", g_BotCount, desiredBots, GetConfiguredMaxBots(), GetFillTarget());
	console_print(id, "Players: humans=%d connected=%d maxplayers=%d minplayers=%d", humanPlayers, connectedClients, g_MaxPlayers, get_pcvar_num(g_CvarPointer[Cvar_MinPlayers]));
	console_print(id, "Rules: time=%s players=%s combined=%s onecon=%d", timeOk ? "yes" : "no", playerCountOk ? "yes" : "no", rulesOk ? "yes" : "no", get_pcvar_num(g_CvarPointer[Cvar_OneCondition]));
	console_print(id, "Reason: %s", reason);

	if (g_RemoveGraceTarget >= 0)
	{
		console_print(id, "Removal grace: target=%d remaining=%d sec", g_RemoveGraceTarget, GetRemovalGraceRemaining());
	}
	else
	{
		console_print(id, "Removal grace: idle (%d sec)", GetRemovalGraceSeconds());
	}

	for (new i = 0; i < g_BotCount; i++)
	{
		new botName[BOT_NAME_BUFFER];
		GetManagedBotName(i, botName, charsmax(botName));
		console_print(id, "Bot %d: userid=%d name=^"%s^" removal_pending=%s", i + 1, g_BotUserIds[i], botName, g_BotKickPending[i] ? "yes" : "no");
	}
}

stock GetBotName(botSlot, botName[], maxLength)
{
	switch (botSlot)
	{
		case 0:
		{
			get_pcvar_string(g_CvarPointer[Cvar_BotName1], botName, maxLength);
		}
		case 1:
		{
			get_pcvar_string(g_CvarPointer[Cvar_BotName2], botName, maxLength);
		}
		default:
		{
			formatex(botName, maxLength, "KGB Bot %d", botSlot + 1);
		}
	}

	trim(botName);

	if (!botName[0])
	{
		formatex(botName, maxLength, "KGB Bot %d", botSlot + 1);
	}
}

stock GetManagedBotName(slot, botName[], maxLength)
{
	new client = FindClientByUserid(g_BotUserIds[slot]);

	if (client)
	{
		get_user_name(client, botName, maxLength);
		return;
	}

	GetBotName(slot, botName, maxLength);
}

stock LogBotEvent(const message[])
{
	log_amx("[KGB Bots] %s", message);
	server_print("[KGB Bots] %s", message);
}

stock LogAdminCommand(id, const action[])
{
	new name[32], authId[35], userid;
	GetActorInfo(id, name, charsmax(name), authId, charsmax(authId), userid);

	new logLine[LOG_BUFFER];
	formatex(logLine, charsmax(logLine), "%s by ^"%s<%d><%s><>^"", action, name, userid, authId);
	LogBotEvent(logLine);
}

stock GetActorInfo(id, name[], nameLen, authId[], authIdLen, &userid)
{
	if (id > 0 && is_user_connected(id))
	{
		get_user_name(id, name, nameLen);
		get_user_authid(id, authId, authIdLen);
		userid = get_user_userid(id);
		return;
	}

	copy(name, nameLen, "Console");
	copy(authId, authIdLen, "SERVER");
	userid = 0;
}

stock MinInt(left, right)
{
	return left < right ? left : right;
}

stock ClampInt(value, minValue, maxValue)
{
	if (value < minValue)
	{
		return minValue;
	}

	if (value > maxValue)
	{
		return maxValue;
	}

	return value;
}

stock ClampHour(value)
{
	return ClampInt(value, 0, 23);
}

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>

#pragma semicolon 1

#define PLUGIN_NAME "KGB Bots"
#define PLUGIN_VERSION "2.4"
#define PLUGIN_AUTHOR "www.mortall.ro"

#define MAX_MANAGED_BOTS 2
#define CONFIG_FILE_NAME "kgbbots.cfg"

#define TASK_ENABLE_PERIODIC_CHECK 10001
#define TASK_ADD_BOT 10002

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
	"amx_norounds"
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
	"0"
};

new g_CvarPointer[Cvar_Count];
new g_MaxPlayers;
new g_BotUserIds[MAX_MANAGED_BOTS];
new g_BotCount;
new g_ConfigPath[128];
new bool:g_IsFirstRound = true;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar("kgbbots", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY);

	register_logevent("Event_RoundEnd", 2, "1=Round_End");
	register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");

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

	server_cmd("exec ^"%s^"", g_ConfigPath);
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

public Task_EnablePeriodicChecks(taskId)
{
	if (get_pcvar_num(g_CvarPointer[Cvar_NoRounds]))
	{
		set_task(30.0, "Task_PeriodicCheck", 0, "", 0, "b");
	}

	CheckConditions();
}

public Task_PeriodicCheck()
{
	CheckConditions();
}

public CheckConditions()
{
	RefreshManagedBots();

	new desiredBots = ShouldBotsBePresent() ? GetDesiredBotCount() : 0;

	if (desiredBots <= 0)
	{
		KickManagedBots();
		return;
	}

	if (g_BotCount > desiredBots)
	{
		KickExtraBots(desiredBots);
		return;
	}

	if (g_BotCount < desiredBots && HasCapacityForDesiredBots(desiredBots))
	{
		ScheduleBotAdd();
	}
}

public Task_AddBot(taskId)
{
	RefreshManagedBots();

	new desiredBots = ShouldBotsBePresent() ? GetDesiredBotCount() : 0;

	if (desiredBots <= g_BotCount || !HasCapacityForDesiredBots(desiredBots))
	{
		return;
	}

	new botSlot = g_BotCount;
	new botName[35];
	GetBotName(botSlot, botName, charsmax(botName));

	new botId = engfunc(EngFunc_CreateFakeClient, botName);

	if (!botId)
	{
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

	g_BotUserIds[g_BotCount] = get_user_userid(botId);
	g_BotCount++;

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

	write_file(g_ConfigPath, "// KGB Bots - Podesavanja");
	write_file(g_ConfigPath, "amx_botname ^"KGB Bot1^"   // Ime prvog bota");
	write_file(g_ConfigPath, "amx_botname2 ^"KGB Bot2^"   // Ime drugog bota");
	write_file(g_ConfigPath, "amx_minplayers ^"10^"   // Botovi se ubacuju ako je broj igraca manji ili jednak ovoj vrednosti.");
	write_file(g_ConfigPath, "amx_starttime ^"0^"   // Od koliko sati da botovi budu na serveru?");
	write_file(g_ConfigPath, "amx_endtime ^"12^"   // Do koliko sati da botovi budu na serveru?");
	write_file(g_ConfigPath, "amx_onecon ^"0^"   // Ako je 1, dovoljan je vremenski ili player-count uslov.");
	write_file(g_ConfigPath, "amx_onebot ^"0^"   // Ako je 1, plugin ubacuje samo jednog bota.");
	write_file(g_ConfigPath, "amx_norounds ^"0^"   // Ako je 1, uslovi se proveravaju periodicki bez round eventa.");
}

stock bool:ShouldBotsBePresent()
{
	new bool:timeOk = IsCurrentHourInWindow();
	new bool:playerCountOk = IsHumanPlayerCountBelowLimit();

	if (get_pcvar_num(g_CvarPointer[Cvar_OneCondition]))
	{
		return timeOk || playerCountOk;
	}

	return timeOk && playerCountOk;
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

stock bool:IsHumanPlayerCountBelowLimit()
{
	new minPlayers = get_pcvar_num(g_CvarPointer[Cvar_MinPlayers]);

	if (minPlayers <= 0)
	{
		return true;
	}

	new players[32], playerCount;
	get_players(players, playerCount, "ch");

	return playerCount <= minPlayers;
}

stock GetDesiredBotCount()
{
	return get_pcvar_num(g_CvarPointer[Cvar_OneBot]) ? 1 : MAX_MANAGED_BOTS;
}

stock bool:HasCapacityForDesiredBots(desiredBots)
{
	return GetConnectedClientCount() + (desiredBots - g_BotCount) <= g_MaxPlayers;
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

stock RefreshManagedBots()
{
	new compactedUserIds[MAX_MANAGED_BOTS];
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
			compactedCount++;
		}
	}

	for (new i = 0; i < MAX_MANAGED_BOTS; i++)
	{
		g_BotUserIds[i] = i < compactedCount ? compactedUserIds[i] : 0;
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

stock KickManagedBots()
{
	for (new i = 0; i < MAX_MANAGED_BOTS; i++)
	{
		KickManagedBotAtSlot(i);
	}

	RefreshManagedBots();
}

stock KickExtraBots(desiredBots)
{
	for (new i = desiredBots; i < MAX_MANAGED_BOTS; i++)
	{
		KickManagedBotAtSlot(i);
	}

	RefreshManagedBots();
}

stock KickManagedBotAtSlot(slot)
{
	if (slot < 0 || slot >= MAX_MANAGED_BOTS || !g_BotUserIds[slot])
	{
		return;
	}

	server_cmd("kick #%d", g_BotUserIds[slot]);
}

stock ScheduleBotAdd()
{
	if (!task_exists(TASK_ADD_BOT))
	{
		set_task(1.5, "Task_AddBot", TASK_ADD_BOT);
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
		default:
		{
			get_pcvar_string(g_CvarPointer[Cvar_BotName2], botName, maxLength);
		}
	}

	trim(botName);

	if (!botName[0])
	{
		copy(botName, maxLength, botSlot == 0 ? "KGB Bot1" : "KGB Bot2");
	}
}

stock ClampHour(value)
{
	if (value < 0)
	{
		return 0;
	}

	if (value > 23)
	{
		return 23;
	}

	return value;
}

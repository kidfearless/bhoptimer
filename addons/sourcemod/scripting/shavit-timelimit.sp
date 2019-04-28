/*
 * shavit's Timer - Dynamic Timelimits
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

// original idea from ckSurf.

#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <shavit>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

// database handle
Database gH_SQL = null;

// base cvars
ConVar mp_do_warmup_period = null;
ConVar mp_freezetime = null;
ConVar mp_ignore_round_win_conditions = null;
ConVar mp_timelimit = null;
ConVar mp_roundtime = null;

// cvars
ConVar gCV_Config = null;
ConVar gCV_DefaultLimit = null;
ConVar gCV_DynamicTimelimits = null;
ConVar gCV_ForceMapEnd = null;
ConVar gCV_MinimumTimes = null;
ConVar gCV_PlayerAmount = null;
ConVar gCV_Style = null;

// misc cache
Handle gH_Timer = null;
EngineVersion gEV_Type = Engine_Unknown;

// table prefix
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Dynamic Timelimits",
	author = "shavit",
	description = "Sets a dynamic value of mp_timelimit and mp_roundtime, based on average map times on the server.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("shavit-wr"))
	{
		SetFailState("shavit-wr is required for the plugin to work.");
	}

	if(gH_SQL == null)
	{
		Shavit_OnDatabaseLoaded();
	}
}

public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();

	LoadTranslations("shavit-common.phrases");

	mp_do_warmup_period = FindConVar("mp_do_warmup_period");
	mp_freezetime = FindConVar("mp_freezetime");
	mp_ignore_round_win_conditions = FindConVar("mp_ignore_round_win_conditions");
	mp_timelimit = FindConVar("mp_timelimit");
	mp_roundtime = FindConVar("mp_roundtime");
	
	if(mp_roundtime != null)
	{
		mp_roundtime.SetBounds(ConVarBound_Upper, false);
	}

	gCV_Config = CreateConVar("shavit_timelimit_config", "1", "Enables the following game settings:\n\"mp_do_warmup_period\" \"0\"\n\"mp_freezetime\" \"0\"\n\"mp_ignore_round_win_conditions\" \"1\"", 0, true, 0.0, true, 1.0);
	gCV_DefaultLimit = CreateConVar("shavit_timelimit_default", "60.0", "Default timelimit to use in case there isn't an average.", 0);
	gCV_DynamicTimelimits = CreateConVar("shavit_timelimit_dynamic", "1", "Use dynamic timelimits.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_ForceMapEnd = CreateConVar("shavit_timelimit_forcemapend", "1", "Force the map to end after the timelimit.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_MinimumTimes = CreateConVar("shavit_timelimit_minimumtimes", "5", "Minimum amount of times required to calculate an average.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!", 0, true, 5.0);
	gCV_PlayerAmount = CreateConVar("shavit_timelimit_playertime", "25", "Limited amount of times to grab from the database to calculate an average.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!\nSet to 0 to have it \"unlimited\".", 0);
	gCV_Style = CreateConVar("shavit_timelimit_style", "1", "If set to 1, calculate an average only from times that the first (default: forwards) style was used to set.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!", 0, true, 0.0, true, 1.0);

	gCV_ForceMapEnd.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	SQL_SetPrefix();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(view_as<bool>(StringToInt(newValue)) && gEV_Type != Engine_TF2)
	{
		gH_Timer = CreateTimer(1.0, Timer_PrintToChat, 0, TIMER_REPEAT);
	}

	else
	{
		delete gH_Timer;
	}
}

public void OnConfigsExecuted()
{
	if(gCV_Config.BoolValue)
	{
		if(mp_do_warmup_period != null)
		{
			mp_do_warmup_period.BoolValue = false;
		}

		if(mp_freezetime != null)
		{
			mp_freezetime.IntValue = 0;
		}

		if(mp_ignore_round_win_conditions != null)
		{
			mp_ignore_round_win_conditions.BoolValue = true;
		}
	}
}

public void OnMapStart()
{
	if(gH_SQL == null)
	{
		return;
	}

	if(gCV_DynamicTimelimits.BoolValue)
	{
		StartCalculating();
	}

	else
	{
		SetLimit(RoundToNearest(gCV_DefaultLimit.FloatValue));
	}

	if(gCV_ForceMapEnd.BoolValue && gH_Timer == null && gEV_Type != Engine_TF2)
	{
		gH_Timer = CreateTimer(1.0, Timer_PrintToChat, 0, TIMER_REPEAT);
	}
}

public void Shavit_OnDatabaseLoaded()
{
	gH_SQL = Shavit_GetDatabase();
	SetSQLInfo();
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

Action SetSQLInfo()
{
	if(gH_SQL == null)
	{
		gH_SQL = Shavit_GetDatabase();

		CreateTimer(0.5, CheckForSQLInfo);
	}

	else
	{
		OnMapStart();

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void SQL_SetPrefix()
{
	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}
	
	char sLine[PLATFORM_MAX_PATH*2];

	while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
	{
		TrimString(sLine);
		strcopy(gS_MySQLPrefix, 32, sLine);

		break;
	}

	delete fFile;
}

void StartCalculating()
{
	if(gH_SQL != null)
	{
		char sMap[160];
		GetCurrentMap(sMap, 160);
		GetMapDisplayName(sMap, sMap, 160);

		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT COUNT(*), SUM(t.time) FROM (SELECT r.time, r.style FROM %splayertimes r WHERE r.map = '%s' AND r.track = 0 %sORDER BY r.time LIMIT %d) t;", gS_MySQLPrefix, sMap, (gCV_Style.BoolValue)? "AND style = 0 ":"", gCV_PlayerAmount.IntValue);

		#if defined DEBUG
		PrintToServer("%s", sQuery);
		#endif

		gH_SQL.Query(SQL_GetMapTimes, sQuery, 0, DBPrio_Low);
	}
}

public void SQL_GetMapTimes(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (TIMELIMIT time selection) SQL query failed. Reason: %s", error);

		return;
	}

	results.FetchRow();
	int iRows = results.FetchInt(0);

	if(iRows >= gCV_MinimumTimes.IntValue)
	{
		float fTimeSum = results.FetchFloat(1);
		float fAverage = (fTimeSum / 60 / iRows);

		if(fAverage <= 1)
		{
			fAverage *= 10;
		}

		else if(fAverage <= 2)
		{
			fAverage *= 9;
		}

		else if(fAverage <= 4)
		{
			fAverage *= 8;
		}

		else if(fAverage <= 8)
		{
			fAverage *= 7;
		}

		else if(fAverage <= 10)
		{
			fAverage *= 6;
		}

		fAverage += 5; // I give extra 5 minutes, so players can actually retry the map until they get a good time.

		if(fAverage < 20)
		{
			fAverage = 20.0;
		}

		else if(fAverage > 120)
		{
			fAverage = 120.0;
		}

		SetLimit(RoundToNearest(fAverage));
	}

	else
	{
		SetLimit(RoundToNearest(gCV_DefaultLimit.FloatValue));
	}
}

void SetLimit(int time)
{
	mp_timelimit.IntValue = time;

	if(mp_roundtime != null)
	{
		mp_roundtime.IntValue = time;
	}
}

public Action Timer_PrintToChat(Handle Timer)
{
	int timelimit = 0;

	if(!GetMapTimeLimit(timelimit) || timelimit == 0)
	{
		return Plugin_Continue;
	}

	int timeleft = 0;
	GetMapTimeLeft(timeleft);

	if(timeleft <= -1 || timeleft >= -3)
	{
		Shavit_StopChatSound();
	}

	switch(timeleft)
	{
		case 3600: Shavit_PrintToChatAll("%T", "Minutes", LANG_SERVER, "60");
		case 1800: Shavit_PrintToChatAll("%T", "Minutes", LANG_SERVER, "30");
		case 1200: Shavit_PrintToChatAll("%T", "Minutes", LANG_SERVER, "20");
		case 600: Shavit_PrintToChatAll("%T", "Minutes", LANG_SERVER, "10");
		case 300: Shavit_PrintToChatAll("%T", "Minutes", LANG_SERVER, "5");
		case 120: Shavit_PrintToChatAll("%T", "Minutes", LANG_SERVER, "2");
		case 60: Shavit_PrintToChatAll("%T", "Seconds", LANG_SERVER, "60");
		case 30: Shavit_PrintToChatAll("%T", "Seconds", LANG_SERVER, "30");
		case 15: Shavit_PrintToChatAll("%T", "Seconds", LANG_SERVER, "15");
		
		case -1:
		{
			Shavit_PrintToChatAll("3..");
		}
		
		case -2:
		{
			Shavit_PrintToChatAll("2..");
		}
		
		case -3:
		{
			Shavit_PrintToChatAll("1..");
		}

		case -4:
		{
			CS_TerminateRound(0.0, CSRoundEnd_Draw, true);
		}
	}

	return Plugin_Continue;
}

public Action CS_OnTerminateRound(float &fDelay, CSRoundEndReason &iReason)
{
	return Plugin_Continue;
}

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <mapzonelib>
#define USES_CHAT_COLORS
#include <shavit>
#include <tr_trigger>


Database gDB_Stages;

int gI_MapID = -1;

bool gB_Late;


public Plugin myinfo =
{
	name = "Shavit - Extra Zones",
	author = "KiD Fearless",
	description = "Adds extra zone support for shavits bhop timer",
	version = "1.0",
	url = "https://steamcommunity.com/id/kidfearless/"
}


//////////////////////////////////////////////
// 						 					//
// 				Forwards					//
// 						 					//
//////////////////////////////////////////////

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;
}

public void OnPluginStart()
{
	RegAdminCmd("sm_addzone", Command_AddZone, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_addzones", Command_AddZone, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_addstart", Command_AddZone, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_addend", Command_AddZone, ADMFLAG_CHANGEMAP);

	char error[256];

	if(SQL_CheckConfig("shavit"))
	{
		gDB_Stages = SQL_Connect("shavit", true, error, 255);

		if(gDB_Stages == null)
		{
			SetFailState("Shavit-Stages startup failed. Reason: %s", error);
		}
	}
	else
	{
		SetFailState("Shavit-Stages startup failed. Reason: Could not find shavit database connection information.");
	}

	if(error[0] != 0)
	{
		LogError(error);
	}

	if(gB_Late)
	{
		if(LibraryExists("mapzonelib"))
		{
			MapZone_OnZonesLoaded();
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "mapzonelib"))
	{
		MapZone_RegisterZoneGroup("shavit-zones");
	}
}

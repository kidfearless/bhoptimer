#include <sourcemod>

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetClientMod", Native_GetClientMod);

	return APLRes_Success;
}

public int Native_GetClientMod(Handle plugin, int args)
{
	return 1;
}
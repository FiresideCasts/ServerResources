#include <tf2>
#include <tf2_stocks>

// TODO: Code cleanup, mostly code dupe and silencing the compiler

const TF_CLASS_COUNT = 10;

// Easily-indexable classlimit convars
ConVar tf_tournament_classlimit[TF_CLASS_COUNT];

ConVar better_offclassing_enabled;
ConVar better_offclassing_classlimit_offclass;

public Plugin myinfo =
{
	name		= "Better Offclassing",
	author		= "Dr. Underscore (James)",
	description = "Combine class limits for offclasses into a single limit.",
	version		= "0.1.1",
	url			= "https://github.com/FiresideCasts/ServerResources"
};

public void OnPluginStart()
{
	tf_tournament_classlimit[TFClass_Scout]	   = FindConVar("tf_tournament_classlimit_scout");
	tf_tournament_classlimit[TFClass_Soldier]  = FindConVar("tf_tournament_classlimit_soldier");
	tf_tournament_classlimit[TFClass_Pyro]	   = FindConVar("tf_tournament_classlimit_pyro");
	tf_tournament_classlimit[TFClass_DemoMan]  = FindConVar("tf_tournament_classlimit_demoman");
	tf_tournament_classlimit[TFClass_Heavy]	   = FindConVar("tf_tournament_classlimit_heavy");
	tf_tournament_classlimit[TFClass_Engineer] = FindConVar("tf_tournament_classlimit_engineer");
	tf_tournament_classlimit[TFClass_Medic]	   = FindConVar("tf_tournament_classlimit_medic");
	tf_tournament_classlimit[TFClass_Sniper]   = FindConVar("tf_tournament_classlimit_sniper");
	tf_tournament_classlimit[TFClass_Spy]	   = FindConVar("tf_tournament_classlimit_spy");

	better_offclassing_enabled				   = CreateConVar("better_offclassing_enabled", "0", "Enables all functionality associated with Better Offclassing");
	better_offclassing_classlimit_offclass	   = CreateConVar("better_offclassing_classlimit_offclass", "1", "Total number of offclasses allowed per team");

	for (int i = 0; i < TF_CLASS_COUNT; i++)
	{
		if (i == TFClass_Unknown)
			continue;

		tf_tournament_classlimit[i].AddChangeHook(OnTFClassLimitChange);
	}

	better_offclassing_enabled.AddChangeHook(OnBetterOffclassingEnabledChange);
	better_offclassing_classlimit_offclass.AddChangeHook(OnBetterOffclassingClasslimitOffclassChange);

	// When a player's team changes, so do their class limits.
	HookEvent("player_team", OnPlayerTeam, EventHookMode_Post);
	// We only want to re-calculate the limits when the class change succeeded -- this is important because of the bias during the switch.
	HookEvent("player_changeclass", OnPlayerChangeClass, EventHookMode_Post);

	// Modify handling of both commands used to change class.
	AddCommandListener(OnJoinClass, "join_class");
	AddCommandListener(OnJoinClass, "joinclass");
}

int min(int a, int b)
{
	return a < b ? a : b;
}

bool IsOffclass(TFClassType class)
{
	return class == TFClass_Pyro
		|| class == TFClass_Heavy
		|| class == TFClass_Engineer
		|| class == TFClass_Sniper
		|| class == TFClass_Spy;
}

bool IsEnabled()
{
	return better_offclassing_enabled.BoolValue;
}

void OnBetterOffclassingEnabledChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar.BoolValue)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsClientInGame(client))
				continue;

			if (IsFakeClient(client))
				continue;

			TFTeam team = TF2_GetClientTeam(client);
			if (team != TFTeam_Red && team != TFTeam_Blue)
				continue;

			SyncClassLimitsToClient(client, TF2_GetClientTeam(client));
		}
	}
	else
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsClientInGame(client))
				continue;

			if (IsFakeClient(client))
				continue;

			for (int i = 0; i < TF_CLASS_COUNT; i++)
			{
				if (i == TFClass_Unknown)
					continue;

				ConVar classlimit_convar = tf_tournament_classlimit[i];

				char   value[8];
				classlimit_convar.GetString(value, sizeof(value));
				classlimit_convar.ReplicateToClient(client, value);
			}
		}
	}
}

void OnBetterOffclassingClasslimitOffclassChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (IsEnabled())
		return;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		if (IsFakeClient(client))
			continue;

		TFTeam team = TF2_GetClientTeam(client);
		if (team != TFTeam_Red && team != TFTeam_Blue)
			continue;

		SyncClassLimitsToClient(client, TF2_GetClientTeam(client));
	}
}

void OnTFClassLimitChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (!IsEnabled())
		return;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		if (IsFakeClient(client))
			continue;

		TFTeam team = TF2_GetClientTeam(client);
		if (team != TFTeam_Red && team != TFTeam_Blue)
			continue;

		SyncClassLimitsToClient(client, TF2_GetClientTeam(client));
	}
}

int CalculateTeamOffClassLimit(TFTeam team, int biasClient = -1, TFClassType biasClass = TFClass_Unknown)
{
	int number_of_offclasses = better_offclassing_classlimit_offclass.IntValue;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		if (TF2_GetClientTeam(client) != team)
			continue;

		TFClassType class;
		if (biasClient != -1 && client == biasClient)
			class = biasClass;
		else
			class = TF2_GetPlayerClass(client);

		if (IsOffclass(class))
		{
			if (--number_of_offclasses == 0)
				break;
		}
	}

	return number_of_offclasses;
}

void CalculateTeamClassLimit(TFTeam team, int limits[TF_CLASS_COUNT], int biasClient = -1, TFClassType biasClass = TFClass_Unknown)
{
	int number_of_offclasses	= CalculateTeamOffClassLimit(team, biasClient, biasClass);

	int pyro_offclass_limit		= number_of_offclasses;
	int heavy_offclass_limit	= number_of_offclasses;
	int engineer_offclass_limit = number_of_offclasses;
	int sniper_offclass_limit	= number_of_offclasses;
	int spy_offclass_limit		= number_of_offclasses;

	if (tf_tournament_classlimit[TFClass_Pyro].IntValue != -1)
		pyro_offclass_limit = min(tf_tournament_classlimit[TFClass_Pyro].IntValue, pyro_offclass_limit);

	if (tf_tournament_classlimit[TFClass_Heavy].IntValue != -1)
		heavy_offclass_limit = min(tf_tournament_classlimit[TFClass_Heavy].IntValue, heavy_offclass_limit);

	if (tf_tournament_classlimit[TFClass_Engineer].IntValue != -1)
		engineer_offclass_limit = min(tf_tournament_classlimit[TFClass_Engineer].IntValue, engineer_offclass_limit);

	if (tf_tournament_classlimit[TFClass_Sniper].IntValue != -1)
		sniper_offclass_limit = min(tf_tournament_classlimit[TFClass_Sniper].IntValue, sniper_offclass_limit);

	if (tf_tournament_classlimit[TFClass_Spy].IntValue != -1)
		spy_offclass_limit = min(tf_tournament_classlimit[TFClass_Spy].IntValue, spy_offclass_limit);

	limits[TFClass_Scout]	 = tf_tournament_classlimit[TFClass_Scout].IntValue;
	limits[TFClass_Soldier]	 = tf_tournament_classlimit[TFClass_Soldier].IntValue;
	limits[TFClass_Pyro]	 = pyro_offclass_limit;
	limits[TFClass_DemoMan]	 = tf_tournament_classlimit[TFClass_DemoMan].IntValue;
	limits[TFClass_Heavy]	 = heavy_offclass_limit;
	limits[TFClass_Engineer] = engineer_offclass_limit;
	limits[TFClass_Sniper]	 = sniper_offclass_limit;
	limits[TFClass_Medic]	 = tf_tournament_classlimit[TFClass_Medic].IntValue;
	limits[TFClass_Spy]		 = spy_offclass_limit;
}

void SyncClassLimitsToClient(client, team, int biasClient = -1, TFClassType biasClass = TFClass_Unknown)
{
	int limits[TF_CLASS_COUNT];
	CalculateTeamClassLimit(team, limits, biasClient, biasClass);

	for (int i = 0; i < TF_CLASS_COUNT; i++)
	{
		if (i == TFClass_Unknown)
			continue;

		char value[8];
		IntToString(limits[i], value, sizeof(value));
		tf_tournament_classlimit[i].ReplicateToClient(client, value);
	}
}

void OnPlayerTeam(Event event, const char[] name, bool ontBroadcast)
{
	if (!IsEnabled())
		return;

	int userid = event.GetInt("userid", -1);
	int client = GetClientOfUserId(userid);

	if (IsFakeClient(client))
		return;

	TFTeam team = view_as<TFTeam>(event.GetInt("team"));

	if (team != TFTeam_Red && team != TFTeam_Blue)
		return;

	SyncClassLimitsToClient(client, team);
}

void OnPlayerChangeClass(Event event, const char[] name, bool ontBroadcast)
{
	if (!IsEnabled())
		return;

	int	   userid		  = event.GetInt("userid", -1);
	int	   changingClient = GetClientOfUserId(userid);
	TFTeam team			  = TF2_GetClientTeam(changingClient);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		if (IsFakeClient(client))
			continue;

		if (TF2_GetClientTeam(client) != team)
			continue;

		SyncClassLimitsToClient(client, team, changingClient, event.GetInt("class", TFClass_Unknown));
	}
}

Action OnJoinClass(int client, const char[] command, int args)
{
	if (!IsEnabled())
		return Plugin_Continue;

	char classname[64];

	GetCmdArg(1, classname, sizeof(classname));

	TFClassType classtype = TFClass_Unknown;

	if (StrEqual(classname, "scout", false))
		classtype = TFClass_Scout;
	else if (StrEqual(classname, "soldier", false))
		classtype = TFClass_Soldier;
	else if (StrEqual(classname, "pyro", false))
		classtype = TFClass_Pyro;
	else if (StrEqual(classname, "demoman", false))
		classtype = TFClass_DemoMan;
	else if (StrEqual(classname, "heavyweapons", false))
		classtype = TFClass_Heavy;
	else if (StrEqual(classname, "engineer", false))
		classtype = TFClass_Engineer;
	else if (StrEqual(classname, "medic", false))
		classtype = TFClass_Medic;
	else if (StrEqual(classname, "sniper", false))
		classtype = TFClass_Sniper;
	else if (StrEqual(classname, "spy", false))
		classtype = TFClass_Spy;
	else
		// Default to whatever TF2 does, which is probably fail.
		return Plugin_Continue;

	TFTeam team = TF2_GetClientTeam(client);

	if (IsOffclass(classtype))
	{
		// Switching from offclass to another offclass is always okay, assuming the limits haven't changed in the interim.
		TFClassType currentClass = TF2_GetPlayerClass(client);
		if (IsOffclass(currentClass))
			return Plugin_Continue;

		if (CalculateTeamOffClassLimit(team) <= 0)
		{
			ShowVGUIPanel(client, team == TFTeam_Red ? "class_red" : "class_blue", null, true);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}
/**
 * vim: set ts=4 :
 * =============================================================================
 * Themes by J-Factor
 * Dynamically change the theme of maps! Enjoy a dark night, sweeping storm or a
 * frosty blizzard without being forced to download another map. Modifiable
 * attributes include the skybox, lighting, fog, particles, soundscapes and
 * color correction.
 * 
 * Credits:
 *			CrimsonGT				Environmental Tools plugin
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
 */

/* INCLUDES *******************************************************************/
#include <sourcemod>
#include <sdktools>
#include <morecolors>

#undef REQUIRE_EXTENSIONS
#include <system2>

/* PREPROCESSOR ***************************************************************/
#pragma semicolon 1
#pragma newdecls required

/* CONSTANTS ******************************************************************/

// Plugin ----------------------------------------------------------------------
#define PLUGIN_NAME		"Themes"
#define PLUGIN_AUTHOR	"J-Factor"
#define PLUGIN_DESC		"Dynamically change the theme of maps!"
#define PLUGIN_VERSION	"0.8"
#define PLUGIN_URL		"http://j-factor.com/"

// Debug -----------------------------------------------------------------------
// #define DEBUG		1 

// Configs ---------------------------------------------------------------------
#define CONFIG_MAPS 		"configs/themes/maps.cfg"
#define CONFIG_THEMES		"configs/themes/themes.cfg"
#define CONFIG_THEMESETS	"configs/themes/themesets.cfg"

// Particles -------------------------------------------------------------------
#define NUM_PARTICLE_FILES	500 // Note: This can never be changed as clients
								// can't redownload the particle manifests

// General ---------------------------------------------------------------------
#define MAX_STAGES		8  // Maximum number of stages in a given map
#define MAX_THEMES		32 // Maximum number of themes in a given map

#define TEAM_RED		2
#define TEAM_BLU		3

#define STYLE_RANDOM	0
#define STYLE_TIME		1

/* VARIABLES ******************************************************************/

// Convars ---------------------------------------------------------------------
ConVar cvPluginEnable  = null;
ConVar cvNextTheme	   = null;
ConVar cvAnnounce	   = null;
ConVar cvParticles     = null;
ConVar cvWind 		   = null;
ConVar cvWindTimer     = null;

// Plugin ----------------------------------------------------------------------
bool pluginEnabled = false;
Handle pluginTimer = null;
ConVar cvPluginTimer = null;

// Key Values ------------------------------------------------------------------
KeyValues kvMaps = null;
KeyValues kvThemes = null;
KeyValues kvThemeSets = null;

// General ---------------------------------------------------------------------
int currentStage = 0; // The current stage of the map
int numStages = 0;    // The number of stages defined for the theme

Handle windTimer = null;
bool windEnabled = false;

// Map Attributes --------------------------------------------------------------
char map[64];

// Theme
char mapTheme[32];
char mapTag[32];

// Skybox
char mapSkybox[32];
int mapSkyboxFogColor;
float mapSkyboxFogStart;
float mapSkyboxFogEnd;
ConVar sv_skyname = null;

// Fog
char mapFogColor[16];
float mapFogStart;
float mapFogEnd;
float mapFogDensity;

// Particles
char mapParticle[64];
float mapParticleHeight;

// Soundscape
char mapSoundscapeInside[32];
char mapSoundscapeOutside[32];

// Lighting, Bloom & Color Correction
char mapLighting[32];
float mapBloom;
char mapColorCorrection1[64];
char mapColorCorrection2[64];

// Misc
char mapDetailSprites[32];
bool mapNoSun;
bool mapBigSun;
bool mapWind;
bool mapNoParticles;
bool mapIndoors;
char mapOverlay[32];

// Map Region
bool mapEstimateRegion;
float mapX1[MAX_STAGES], mapX2[MAX_STAGES],
	mapY1[MAX_STAGES], mapY2[MAX_STAGES],
	mapZ[MAX_STAGES];
	
// Extra
int mapCCEntity1;
int mapCCEntity2;

// Theme -----------------------------------------------------------------------
char themes[MAX_THEMES][32];

// Time Period
int themeStart[MAX_THEMES];
int themeDuration[MAX_THEMES];

// Random Chance
float themeChance[MAX_THEMES]; // Chance for each theme

// Number of themes defined for the current map
int numThemes = 0;

// Number of themes that do not have a chance defined for them
int numUnknownChanceThemes = 0;

// Total chance for all themes that have a chance defined
float totalChance = 0.0;

// Theme selection style
int selectionStyle = STYLE_RANDOM;

enum struct FishInfo
{
	char model[PLATFORM_MAX_PATH];
	float pos[3];
	float range;
	int count;
}

ArrayList fishes = null;

bool bSystem2 = false;
	
/* PLUGIN *********************************************************************/
public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESC,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	if(LibraryExists("system2") ||
		GetExtensionFileStatus("system2.ext") == 1) {
		bSystem2 = true;
	}

	return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "system2")) {
		bSystem2 = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "system2")) {
		bSystem2 = false;
	}
}

ConVar cvManifests = null;
ConVar cvAutoBZ2 = null;
ConVar cvBZ2Compression = null;
ConVar cvUpload = null;
ConVar cvUsername = null;
ConVar cvPass = null;
ConVar cvDeleteBZ2 = null;
ConVar cvUrl = null;
ConVar cvEstimateMethod = null;
ConVar cvDefaultThemeset = null;
ConVar cvBZ2CopyFolder = null;

void ClampCompression(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int compress = StringToInt(newValue);

	switch(compress) {
		case 0: { convar.IntValue = 1; }
		case 2: { convar.IntValue = 3; }
		case 4: { convar.IntValue = 5; }
		case 6: { convar.IntValue = 6; }
		case 8: { convar.IntValue = 9; }
	}

	if(compress < 0) {
		convar.IntValue = 1;
	} else if(compress > 9) {
		convar.IntValue = 9;
	}
}

/* METHODS ********************************************************************/

/* OnPluginStart()
**
** When the plugin is loaded.
** -------------------------------------------------------------------------- */
public void OnPluginStart()
{
	// Confirm this is TF2
	char strModName[32]; GetGameFolderName(strModName, sizeof(strModName));
	if (!StrEqual(strModName, "tf")) SetFailState("This plugin is TF2 only.");

	// Convars
	CreateConVar("sm_themes_version", PLUGIN_VERSION, "Themes version", FCVAR_REPLICATED|FCVAR_NOTIFY);
	cvPluginEnable = CreateConVar("sm_themes_enable", "1", "Enables Themes");
	cvPluginTimer  = CreateConVar("sm_themes_timer", "10.0");
	cvNextTheme = 	 CreateConVar("sm_themes_next_theme", "", "Forces the next map to use the given theme");
	cvAnnounce =     CreateConVar("sm_themes_announce", "1", "Whether or not to announce the current theme");
	cvParticles =    CreateConVar("sm_themes_particles", "1", "Enables or disables custom particles for themes");
	cvWind	    =    CreateConVar("sm_themes_wind", "0");
	cvWindTimer	  =  CreateConVar("sm_themes_wind_timer", "0.2");

	cvManifests = CreateConVar("sm_themes_create_manifests", "1");
	cvAutoBZ2 = CreateConVar("sm_themes_bz2_manifests", "1");
	cvBZ2Compression = CreateConVar("sm_themes_bz2_compression", "9", "1,3,5,7,9");
	cvUpload = CreateConVar("sm_themes_upload_ftp", "0");
	cvUsername = CreateConVar("sm_themes_ftp_user", "");
	cvPass = CreateConVar("sm_themes_ftp_pass", "");
	cvDeleteBZ2 = CreateConVar("sm_themes_delete_bz2", "1");
	cvUrl = CreateConVar("sm_themes_ftp_url", "");
	cvEstimateMethod = CreateConVar("sm_themes_region_method", "0", "0 == entities, 1 == m_WorldMaxs/Mins");
	cvDefaultThemeset = CreateConVar("sm_themes_default_themeset", "standard");
	cvBZ2CopyFolder = CreateConVar("sm_themes_bz2_folder", "");

	RegAdminCmd("sm_themes_reload", ConCommand_ReloadTheme, ADMFLAG_GENERIC);

	cvPluginEnable.AddChangeHook(Event_EnableChange);
	cvWind.AddChangeHook(Event_WindEnableChange);
	cvWindTimer.AddChangeHook(Event_WindTimerChange);
	cvNextTheme.AddChangeHook(Event_NextThemeChange);

	cvBZ2Compression.AddChangeHook(ClampCompression);

	sv_skyname = FindConVar("sv_skyname");

	// Configuration
	kvMaps = new KeyValues("Maps");
	kvThemes = new KeyValues("Themes");
	kvThemeSets = new KeyValues("Themesets");
	
	// Translations
	LoadTranslations("themes.phrases");

	// Execute main config
	AutoExecConfig(true, "themes");

	// Initialize
	windEnabled = cvWind.BoolValue;
	Initialize(cvPluginEnable.BoolValue);
}

Action ConCommand_ReloadTheme(int client, int args)
{
	Initialize(false, false);

	bool arg = (args > 0);

	if(arg) {
		char str[32];
		GetCmdArg(1, str, sizeof(str));

		cvAnnounce.BoolValue = false;
		cvNextTheme.SetString(str);
		cvAnnounce.BoolValue = true;
	}

	if(cvPluginEnable.BoolValue) {
		Initialize(true, false);
		StartTheme(false);
	}

	if(args) {
		cvNextTheme.SetString("");
	}

	return Plugin_Handled;
}

/* Event_EnableChange()
**
** When the plugin is enabled/disabled.
** -------------------------------------------------------------------------- */
void Event_EnableChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	Initialize(strcmp(newValue, "1") == 0);
}

void Event_WindEnableChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	windEnabled = strcmp(newValue, "1") == 0;
}

void Event_WindTimerChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(windTimer) {
		KillTimer(windTimer);
	}
	windTimer = null;

	if (pluginEnabled) {
		float flValue = StringToFloat(newValue);
		windTimer = CreateTimer(flValue, Timer_Wind, 0, TIMER_REPEAT);
	}
}

/* Initialize()
**
** Initializes the plugin.
** -------------------------------------------------------------------------- */
void Initialize(bool enable, bool print=true)
{
	if (enable && !pluginEnabled) {
		// Enable!
		HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
		HookEvent("teamplay_round_win", Event_RoundEnd);
		HookEvent("teamplay_round_stalemate", Event_RoundEnd);
		HookEvent("player_team", Event_PlayerTeam);
	
		pluginTimer = CreateTimer(cvPluginTimer.FloatValue, Timer_Plugin, 0, TIMER_REPEAT);
		windTimer = CreateTimer(cvWindTimer.FloatValue, Timer_Wind, 0, TIMER_REPEAT);
		pluginEnabled = true;
		
		if(print) {
			CPrintToChatAll("%t", "Plugin_Enable", PLUGIN_NAME);
		}
	} else if (!enable && pluginEnabled) {
		// Disable!
		UnhookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
		UnhookEvent("teamplay_round_win", Event_RoundEnd);
		UnhookEvent("teamplay_round_stalemate", Event_RoundEnd);
		UnhookEvent("player_team", Event_PlayerTeam);
		
		KillTimer(pluginTimer);
		pluginTimer = null;

		KillTimer(windTimer);
		windTimer = null;

		pluginEnabled = false;
		
		if(print) {
			CPrintToChatAll("%t", "Plugin_Disable", PLUGIN_NAME);
		}
	}
}

/* Event_NextThemeChange()
**
** When the next theme is changed.
** -------------------------------------------------------------------------- */
void Event_NextThemeChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!StrEqual(newValue, "")) {
		char nextTheme[32];
		char nextTag[32];

		if (kvThemes.JumpToKey(newValue)) {
			kvThemes.GetString("name", nextTheme, sizeof(nextTheme), "Unnamed Theme");
			kvThemes.GetString("tag", nextTag, sizeof(nextTag), "{olive}");
		
			kvThemes.GoBack();
			
			if (cvAnnounce.BoolValue) {
				CPrintToChatAll("%t", "Announce_NextTheme", nextTag, nextTheme);
			}
		}
	}
}
/* Timer_Wind()
**
** Timer for moving ropes, simulating wind. Called every 0.2s.
** ------------------------------------------------------------------------- */
Action Timer_Wind(Handle timer)
{
	// Apply Wind
	if (mapWind && windEnabled) {
		int ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "move_rope")) != -1) {
			char force[32];
			Format(force, sizeof(force), "-%d -%d 0", GetRandomInt(300, 1000), GetRandomInt(300, 1000));
			
			SetVariantString(force);
			AcceptEntityInput(ent, "SetForce");
		}
		
		ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "keyframe_rope")) != -1) {
			char force[32];
			Format(force, sizeof(force), "-%d -%d 0", GetRandomInt(300, 1000), GetRandomInt(300, 1000));
			
			SetVariantString(force);
			AcceptEntityInput(ent, "SetForce");
		}
	}

	return Plugin_Continue;
}

/* Timer_Plugin()
**
** Timer for general plugin fixes. Called every 10s.
** ------------------------------------------------------------------------- */
Action Timer_Plugin(Handle timer)
{
	// Possible fix for some players not seeing color correction at times?
	if (IsValidEntity(mapCCEntity1)) {
		DispatchKeyValue(mapCCEntity1, "filename", mapColorCorrection1);
	}
	if (IsValidEntity(mapCCEntity2)) {
		DispatchKeyValue(mapCCEntity2, "filename", mapColorCorrection2);
	}

	return Plugin_Continue;
}

void StartTheme(bool download=true)
{
	if (pluginEnabled) {
		// Initializes the configuration
		InitConfig();
		
		// Loads the configuration
		if (LoadConfig()) {
			if(download) {
				// Updates the downloads table
				UpdateDownloadsTable();
			}
			
			// Log the theme values
			LogTheme();
			
			// Applys the loaded configuration for the map
			ApplyConfigMap();
			
			// Applys the loaded configuration for the current round
			ApplyConfigRound();
		}
	}
}

/* OnMapStart()
**
** When the a map starts.
** -------------------------------------------------------------------------- */
public void OnMapStart()
{
	StartTheme();
}

/* InitConfig()
**
** Initializes the configuration, resetting the previous map attributes.
** -------------------------------------------------------------------------- */
void InitConfig()
{
	char file[128];
	
	// Load the Maps config
	BuildPath(Path_SM, file, sizeof(file), CONFIG_MAPS);
	kvMaps.ImportFromFile(file);
	
	// Load the Themes config
	BuildPath(Path_SM, file, sizeof(file), CONFIG_THEMES);
	kvThemes.ImportFromFile(file);
	
	// Load the Themesets config
	BuildPath(Path_SM, file, sizeof(file), CONFIG_THEMESETS);
	kvThemeSets.ImportFromFile(file);

	// Reset the map attributes
	map = "";
	
	mapTheme = "Default";
	mapTag = "{olive}";
	
	// Skybox
	mapSkybox[0]      = '\0';
	mapSkyboxFogColor = -1;
	mapSkyboxFogStart = -1.0;
	mapSkyboxFogEnd	  = -1.0;
	
	// Fog
	mapFogColor[0] = '\0';
	mapFogStart	   = -1.0;
	mapFogEnd	   = -1.0;
	mapFogDensity  = -1.0;
	
	// Particles
	mapParticle[0]	   = '\0';
	mapParticleHeight  = 800.0;
	
	// Soundscape
	mapSoundscapeInside[0]  = '\0';
	mapSoundscapeOutside[0] = '\0';
	
	// Lighting, Bloom & Color Correction
	mapLighting[0] = '\0';
	mapBloom 	   = -1.0;
	mapColorCorrection1[0] = '\0';
	mapColorCorrection2[0] = '\0';
	
	// Misc
	mapDetailSprites[0] = '\0';
	mapNoSun  = false;
	mapBigSun = false;
	mapWind   = false;
	mapNoParticles = false;
	mapIndoors = false;
	mapOverlay[0] = '\0';
	
	// Region
	numStages = 0;
	mapEstimateRegion = true;
	
	for (int i = 0; i < MAX_STAGES; i++) {
		mapX1[i] = 0.0;
		mapX2[i] = 0.0;
		mapY1[i] = 0.0;
		mapY2[i] = 0.0;
		mapZ[i] = 0.0;
	}
	
	// Reset etc
	numThemes = 0;
	numUnknownChanceThemes = 0;
	totalChance = 0.0;
	selectionStyle = STYLE_RANDOM;

	delete fishes;
}

/* LoadConfig()
**
** Loads the configuration.
** -------------------------------------------------------------------------- */
bool LoadConfig()
{
	char themeConvar[64];
    
	// Read the map name and check if it's in the config
	GetCurrentMap(map, sizeof(map));
    
    // Check if we should load a specific theme or randomly select one
	cvNextTheme.GetString(themeConvar, sizeof(themeConvar));
	
	if (kvMaps.JumpToKey(map)) {
		// Map is defined in the config
		char themeSet[32];
		
		// Read ThemeSet
		kvMaps.GetString("themeset", themeSet, sizeof(themeSet), "");
		
		// Check if the map is using a ThemeSet
		if (!StrEqual(themeSet, "")) {
			if (kvThemeSets.JumpToKey(themeSet)) {
				// Read all themes in ThemeSet
				ReadThemeSet(kvThemeSets);
				
				kvThemeSets.GoBack();
			}
		} else {
			// Treat map config as ThemeSet and read all themes
			ReadThemeSet(kvMaps);
		}
		
		// Read Map Region
		ReadMapRegion(kvMaps);
		
		// Read Theme
		if (!StrEqual(themeConvar, "")) {
			// Use theme convar
			ReadTheme(themeConvar);
			
			// Check if this theme is defined for the map
			for (int i = 0; i < numThemes; i++) {
				if (StrEqual(themes[i], themeConvar)) {
					// Read custom attributes for this theme that are specific to this map
					ReadThemeAttributesNumber(kvMaps, i);
					
					break;
				}
			}
			
			// Reset theme convar
			cvNextTheme.SetString("");
		} else if (selectionStyle == STYLE_TIME) {
			// Time period for themes
			int i, j = 0;
			
			for (i = 0; i < numThemes; i++) {
				if (themeDuration[i] == 0) {
					j = i;
					continue;
				}
				
				int time = GetTimeOfDay();
				
				if (time < themeStart[i]) {
					time += (24 * 60 * 60) - themeStart[i];
				} else {
					time -= themeStart[i];
				}
				
				if (time <= themeDuration[i]) {
					ReadTheme(themes[i]);
					ReadThemeAttributesNumber(kvMaps, i);

					break;
				}
			}
			
			if (i == numThemes) {
				ReadTheme(themes[j]);
				ReadThemeAttributesNumber(kvMaps, j);
			}
		} else {
			// Random chance for themes
			float randomNum = GetRandomFloat();
			
			for (int i = 0; i < numThemes; i++) {
				// If a chance hasn't been defined for this theme divide the remaining undefined chance equally
				if (themeChance[i] == -1.0) {
					themeChance[i] = (1.0 - totalChance)/numUnknownChanceThemes;
				}
				
				if (randomNum <= themeChance[i]) {
					ReadTheme(themes[i]);
					ReadThemeAttributesNumber(kvMaps, i);

					break;
				}
				
				randomNum -= themeChance[i];
			}
		}
		
		// Read custom attributes for all themes that are specific to this map
		ReadThemeAttributes(kvMaps);

		if(kvMaps.JumpToKey("fish_pools")) {
			delete fishes;
			fishes = new ArrayList(sizeof(FishInfo));

			if(kvMaps.GotoFirstSubKey()) {
				do {
					FishInfo info;
					kvMaps.GetString("model", info.model, sizeof(info.model), "models/error.mdl");

					PrecacheModel(info.model);

					info.count = kvMaps.GetNum("count", 10);
					info.range = kvMaps.GetFloat("range", 150.0);

					kvMaps.GetVector("pos", info.pos);

					fishes.PushArray(info, sizeof(info));
				} while(kvMaps.GotoNextKey());

				kvMaps.GoBack();
			}

			kvMaps.GoBack();
		}

		// Reset theme convar
		cvNextTheme.SetString("");
		
		// Go back
		kvMaps.GoBack();
		
		return true;
	} else {
		char themeSet[32];
		cvDefaultThemeset.GetString(themeSet, sizeof(themeSet));

		// Check if the map is using a ThemeSet
		if(!StrEqual(themeSet, "")) {
			if (kvThemeSets.JumpToKey(themeSet)) {
				// Read all themes in ThemeSet
				ReadThemeSet(kvThemeSets);
				
				kvThemeSets.GoBack();
			}

			if (!StrEqual(themeConvar, "")) {
				// Use theme convar
				ReadTheme(themeConvar);
				
				// Reset theme convar
				cvNextTheme.SetString("");
			} else if (selectionStyle == STYLE_TIME) {
				// Time period for themes
				int i, j = 0;
				
				for (i = 0; i < numThemes; i++) {
					if (themeDuration[i] == 0) {
						j = i;
						continue;
					}
					
					int time = GetTimeOfDay();
					
					if (time < themeStart[i]) {
						time += (24 * 60 * 60) - themeStart[i];
					} else {
						time -= themeStart[i];
					}
					
					if (time <= themeDuration[i]) {
						ReadTheme(themes[i]);

						break;
					}
				}
				
				if (i == numThemes) {
					ReadTheme(themes[j]);
				}
			} else {
				// Random chance for themes
				float randomNum = GetRandomFloat();
				
				for (int i = 0; i < numThemes; i++) {
					// If a chance hasn't been defined for this theme divide the remaining undefined chance equally
					if (themeChance[i] == -1.0) {
						themeChance[i] = (1.0 - totalChance)/numUnknownChanceThemes;
					}
					
					if (randomNum <= themeChance[i]) {
						ReadTheme(themes[i]);

						break;
					}
					
					randomNum -= themeChance[i];
				}
			}

			// Reset theme convar
			cvNextTheme.SetString("");

			return true;
		}

		// Reset theme convar
		cvNextTheme.SetString("");
		
		return false;
	}
}

/* ReadThemeSet()
**
** Reads a ThemeSet from the current position in the given KeyValues.
** -------------------------------------------------------------------------- */
void ReadThemeSet(KeyValues kv)
{
	char style[16];
	char key[8] = "theme1"; 
	
	// Read the Theme Selection Style
	kv.GetString("style", style, sizeof(style), "");
	
	if (StrEqual(style, "random")) {
		selectionStyle = STYLE_RANDOM;
	} else if (StrEqual(style, "time")) {
		selectionStyle = STYLE_TIME;
	}
	
	// Find each theme
	while (kv.JumpToKey(key)) {
		char time[6];
		
		// Read Theme Name
		kvThemeSets.GetString("theme", themes[numThemes], 32, "");
		
		// Read Time Period
		kvThemeSets.GetString("start", time, sizeof(time), "");
		themeStart[numThemes] = StringToTimeOfDay(time);
		
		kvThemeSets.GetString("end", time, sizeof(time), "");
		themeDuration[numThemes] = StringToTimeOfDay(time);
		
		if (themeDuration[numThemes] < themeStart[numThemes]) {
			themeDuration[numThemes] += 86400 - themeStart[numThemes];
		}
		
		// Read Random Chance
		themeChance[numThemes] = kvThemeSets.GetFloat("chance", -1.0);
		
		if (themeChance[numThemes] != -1.0) {
			totalChance += themeChance[numThemes];
		} else {
			numUnknownChanceThemes++;
		}
		
		kvThemeSets.GoBack();
		
		// Check for next theme
		Format(key, sizeof(key), "theme%i", ++numThemes + 1);
	}
}

/* ReadMapRegion()
**
** Reads the map region.
** -------------------------------------------------------------------------- */
void ReadMapRegion(KeyValues kv)
{
	if (kv.JumpToKey("region")) {
		mapEstimateRegion = false;
	
		// Read the region for each stage of the map
		for (int i = 0; i < MAX_STAGES; i++) {
			char stage[8];
			Format(stage, sizeof(stage), "stage%i", i + 1);
			
			if (kv.JumpToKey(stage)) {
				float n1, n2;
				
				n1 = kv.GetFloat("x1", 0.0);
				n2 = kv.GetFloat("x2", 0.0);
				
				if (n1 > n2) {
					mapX1[i] = n2;
					mapX2[i] = n1;
				} else {
					mapX1[i] = n1;
					mapX2[i] = n2;
				}
				
				n1 = kv.GetFloat("y1", 0.0);
				n2 = kv.GetFloat("y2", 0.0);
				
				if (n1 > n2) {
					mapY1[i] = n2;
					mapY2[i] = n1;
				} else {
					mapY1[i] = n1;
					mapY2[i] = n2;
				}
				
				mapZ[i] = kv.GetFloat("z", 0.0);
				
				numStages++;
				
				kv.GoBack();
			}
		}
		
		kv.GoBack();
	}
}

/* ReadTheme()
**
** Reads a theme.
** -------------------------------------------------------------------------- */
void ReadTheme(const char[] theme)
{
	if (kvThemes.JumpToKey(theme)) {
		// Read Name
		kvThemes.GetString("name", mapTheme, sizeof(mapTheme), "Unnamed Theme");
		
		// Read Tag
		kvThemes.GetString("tag", mapTag, sizeof(mapTag), mapTag);
		
		// Read Attributes
		ReadThemeAttributes(kvThemes);
		
		kvThemes.GoBack();
	}
}

/* ReadThemeAttributesNumber()
**
** Jumps to the key holding the given theme number and reads theme attributes.
** -------------------------------------------------------------------------- */
void ReadThemeAttributesNumber(KeyValues kv, int num)
{
	char key[8];
	
	Format(key, sizeof(key), "theme%i", num + 1);
	
	if (kv.JumpToKey(key)) {
		ReadThemeAttributes(kv);
		kv.GoBack();
	}
}

/* ReadThemeAttributes()
**
** Reads theme attributes from the current position in the given KeyValues.
** -------------------------------------------------------------------------- */
void ReadThemeAttributes(KeyValues kv)
{
	// Read Skybox
	if (kv.JumpToKey("skybox")) {
		kv.GetString("name", mapSkybox, sizeof(mapSkybox), mapSkybox);
		
		// Read Skybox Fog
		if (kv.JumpToKey("fog")) {
			char skyboxFogColor[16];
			
			// Read Skybox Fog Color
			// Note: We need an integer for this as we directly send the prop
			// value to players
			kv.GetString("color", skyboxFogColor, sizeof(skyboxFogColor), "");
			
			if (!StrEqual(skyboxFogColor, "")) {
				char buffers[3][8];
				int num = ExplodeString(skyboxFogColor, " ", buffers, 3, 8);
				
				if (num == 3) {
					mapSkyboxFogColor = StringToInt(buffers[0]) | StringToInt(buffers[1]) << 8 | StringToInt(buffers[2]) << 16;
				}
			}
			
			// Read Skybox Fog Start
			mapSkyboxFogStart = kv.GetFloat("start", mapSkyboxFogStart);
			
			// Read Skybox Fog End
			mapSkyboxFogEnd = kv.GetFloat("end", mapSkyboxFogEnd);
			
			kv.GoBack();
		}

		kv.GoBack();
	}
	
	// Read Fog
	if (kv.JumpToKey("fog")) {
		// Read Fog Color
		kv.GetString("color", mapFogColor, sizeof(mapFogColor), mapFogColor);
		
		// Read Fog Start
		mapFogStart = kv.GetFloat("start", mapFogStart);
		
		// Read Fog End
		mapFogEnd = kv.GetFloat("end", mapFogEnd);
		
		// Read Fog Density
		mapFogDensity = kv.GetFloat("density", mapFogDensity);
		
		kv.GoBack();
	}
	
	// Read Particles
	if (kv.JumpToKey("particles")) {
		// Read Particle Name
		kv.GetString("name", mapParticle, sizeof(mapParticle), mapParticle);
		
		// Read Particle Height
		mapParticleHeight = kv.GetFloat("height", mapParticleHeight);
		
		kv.GoBack();
	}
	
	// Read Soundscape
	if (kv.JumpToKey("soundscape")) {
		// Read Inside Soundscape
		kv.GetString("inside", mapSoundscapeInside, sizeof(mapSoundscapeInside), mapSoundscapeInside);
		
		// Read Outside Soundscape
		kv.GetString("outside", mapSoundscapeOutside, sizeof(mapSoundscapeOutside), mapSoundscapeOutside);
		
		kv.GoBack();
	}
	
	// Read Lighting
	kv.GetString("lighting", mapLighting, sizeof(mapLighting), mapLighting);

	// Read Bloom
	mapBloom = kv.GetFloat("bloom", mapBloom);
	
	// Read Color Correction
	kv.GetString("color1", mapColorCorrection1, sizeof(mapColorCorrection1), mapColorCorrection1);
	kv.GetString("color2", mapColorCorrection2, sizeof(mapColorCorrection2), mapColorCorrection2);
	
	// Read Detail Sprites
	kv.GetString("detail", mapDetailSprites, sizeof(mapDetailSprites), mapDetailSprites);
	
	// Read No Sun
	mapNoSun = (kv.GetNum("nosun", mapNoSun) == 1);
	
	// Read Big Sun
	mapBigSun = (kv.GetNum("bigsun", mapBigSun) == 1);
	
	// Read Wind
	mapWind = (kv.GetNum("wind", mapWind) == 1);
	
	// Read No Particles
	mapNoParticles = (kv.GetNum("noparticles", mapNoParticles) == 1);
	
	// Read Indoors
	mapIndoors = (kv.GetNum("indoors", mapIndoors) == 1);
	
	// Read Overlay
	kv.GetString("overlay", mapOverlay, sizeof(mapOverlay), mapOverlay);
}

/* UpdateDownloadsTable()
**
** Updates the downloads table.
** -------------------------------------------------------------------------- */
void UpdateDownloadsTable()
{
	char filename[96];
	
	// Handle Particles
	if (cvParticles.BoolValue) {
		HandleParticleFiles();
		
		AddFileToDownloadsTable("materials/particles/themes_leaf.vmt");
		AddFileToDownloadsTable("materials/particles/themes_leaf.vtf");
	}
	
	// Handle Color Correction
	if (!StrEqual(mapColorCorrection1, "")) {
		Format(filename, sizeof(filename), "materials/correction/%s", mapColorCorrection1);
		AddFileToDownloadsTable(filename);
	}
	
	if (!StrEqual(mapColorCorrection2, "")) {
		Format(filename, sizeof(filename), "materials/correction/%s", mapColorCorrection2);
		AddFileToDownloadsTable(filename);
	}

	if(fishes != null) {
		for(int i = 0; i < fishes.Length; ++i) {
			FishInfo info;
			fishes.GetArray(i, info, sizeof(info));

			AddFileToDownloadsTable(info.model);
		}
	}
}

void OnMapManifestFTP(bool success, const char[] error, System2FTPRequest request, System2FTPResponse response)
{
	if(success) {
		//???

		if(cvDeleteBZ2.BoolValue) {

		}
	} else {
		//???
	}
}

void OnCopyMapBZ2(bool success, const char[] from, const char[] to)
{
	if(success) {
		DeleteFile(from);
	} else {
		if(!RenameFile(to, from, true)) {
			LogMessage("Error: Could not copy bz2 to: %s", to);
		}
	}
}

void OnCompressMapParticles(bool success, const char[] command, System2ExecuteOutput output, DataPack data)
{
	data.Reset();

	int len = data.ReadCell();

	char[] filename = new char[len];
	data.ReadString(filename, len);

	delete data;

	if(success) {
		if(cvUpload.BoolValue) {
			char url[64];
			cvUrl.GetString(url, sizeof(url));

			System2FTPRequest ftp = new System2FTPRequest(OnMapManifestFTP, "%s/tf/maps/", url);

			char usrname[32];
			cvUsername.GetString(usrname, sizeof(usrname));

			char pass[32];
			cvPass.GetString(pass, sizeof(pass));

			ftp.SetAuthentication(usrname, pass);
			ftp.SetInputFile(filename);
			ftp.StartRequest();
		}

		char folder[PLATFORM_MAX_PATH];
		cvBZ2CopyFolder.GetString(folder, sizeof(folder));

		if(!StrEqual(folder, "")) {
			StrCat(folder, sizeof(folder), filename);

			System2_CopyFile(OnCopyMapBZ2, filename, folder);
		}
	} else {
		LogMessage("Error: Could not compress particle manifest: %s", filename);
	}
}

void OnCopyMapTemplate(bool success, const char[] from, const char[] to)
{
	if(success) {
		AddFileToDownloadsTable(to);

		if(cvAutoBZ2.BoolValue) {
			char bz2[PLATFORM_MAX_PATH];
			strcopy(bz2, sizeof(bz2), to);
			StrCat(bz2, sizeof(bz2), ".bz2");

			CompressLevel compress = LEVEL_9;
			switch(cvBZ2Compression.IntValue) {
				case 1: { compress = LEVEL_1; }
				case 3: { compress = LEVEL_3; }
				case 5: { compress = LEVEL_5; }
				case 7: { compress = LEVEL_7; }
				case 9: { compress = LEVEL_9; }
			}

			DataPack data = new DataPack();

			data.WriteCell(strlen(bz2)+1);
			data.WriteString(bz2);

			if(!System2_Compress(OnCompressMapParticles, to, bz2, ARCHIVE_BZIP2, compress, data)) {
				LogMessage("Error: Could not compress particle manifest: %s", to);
			}
		}
	} else {
		LogMessage("Error: Could not copy particle template to: %s", to);
	}
}

void HandleMapParticleManifest(const char[] mapname)
{
	char file[96];
	Format(file, sizeof(file), "maps/%s_particles.txt", mapname);

	if(!FileExists(file, true)) {
		if(cvManifests.BoolValue && bSystem2) {
			LogMessage("Warning: Particles file does not exist: %s, creating a new one", file);

			char template[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, template, sizeof(template), "data/themes/particles_template.txt");

			System2_CopyFile(OnCopyMapTemplate, template, file);
		} else {
			LogMessage("Error: Particles file does not exist: %s", file);
		}
	} else {
		AddFileToDownloadsTable(file);
	}
}

/* HandleParticleFiles()
**
** Handles custom particle files.
** -------------------------------------------------------------------------- */
void HandleParticleFiles()
{
	char file[96];
	
	// Add ALL map particle manifest files (due to waffle bug)
	/*if (kvMaps.GotoFirstSubKey()) {
		do {
			kvMaps.GetSectionName(file, sizeof(file));
			HandleMapParticleManifest(file);
		} while (kvMaps.GotoNextKey());
		
		kvMaps.GoBack();
	}*/

	GetCurrentMap(file, sizeof(file));
	HandleMapParticleManifest(file);

	// Add particle files
	for (int i = 1; i <= NUM_PARTICLE_FILES; i++) {
		Format(file, sizeof(file), "particles/custom_particles%03i.pcf", i);
	
		if (FileExists(file, true)) {
			AddFileToDownloadsTable(file);
		}
	}
}

/* ApplyConfigMap()
**
** Applys the loaded configuration to the current map. Not all attributes can be
** applied here. Some must be reapplied every round start.
** -------------------------------------------------------------------------- */
void ApplyConfigMap()
{
	int ent;
	char detailMaterial[48];
	
	// Apply Skybox
	if (!StrEqual(mapSkybox, "")) {
		DispatchKeyValue(0, "skyname", mapSkybox);
		sv_skyname.SetString(mapSkybox, true);
	}
	
	// Apply Fog
	ent = FindEntityByClassname(-1, "env_fog_controller");
	
	if (ent != -1) {
		// Apply Fog Color
		if (!StrEqual(mapFogColor, "")) {
			DispatchKeyValue(ent, "fogblend", "0");
			DispatchKeyValue(ent, "fogcolor", mapFogColor);
		}
		
		// Apply Fog Start
		if (mapFogStart != -1.0) {
			DispatchKeyValueFloat(ent, "fogstart", mapFogStart);
		}
		
		// Apply Fog End
		if (mapFogEnd != -1.0) {
			DispatchKeyValueFloat(ent, "fogend", mapFogEnd);
		}
		
		// Apply Fog Density
		if (mapFogDensity != -1.0) {
			DispatchKeyValueFloat(ent, "fogmaxdensity", mapFogDensity);
		}
	}
	
	// Apply Indoors
	if (mapIndoors) {
		strcopy(mapSoundscapeInside, sizeof(mapSoundscapeInside), mapSoundscapeOutside);
	}
	
	// Apply No Particles
	if (mapNoParticles) {
		bool p = false;
		ent = -1;
		char targetname[64];
		
		while ((ent = FindEntityByClassname(ent, "info_particle_system")) != -1) {
			GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
			
			if ((StrContains(targetname, "particle_rain") != -1) ||
					(StrContains(targetname, "particle_snow") != -1) ||
					(StrContains(targetname, "particle_waterdrops") != -1)) {
				AcceptEntityInput(ent, "Kill");
				p = true;
			}
		}
		
		// Check if we removed any particles
		if (p) {
			// Change the soundscape to stop rain sounds with no rain particles
			if (StrEqual(mapSoundscapeInside, "")) {
				mapSoundscapeInside = "Lumberyard.Inside";
			}
			
			if (StrEqual(mapSoundscapeOutside, "")) {
				mapSoundscapeOutside = "Lumberyard.Outside";
			}
		}
	}

	// Apply Soundscape
	if (!StrEqual(mapSoundscapeInside, "") || !StrEqual(mapSoundscapeOutside, "")) {
		ApplySoundscape();
	}
	
	// Apply Lighting
	if (!StrEqual(mapLighting, "")) {
		SetLightStyle(0, mapLighting);
	}
	
	// Apply Detail Sprites
	if (!StrEqual(mapDetailSprites, "")) {
		Format(detailMaterial, sizeof(detailMaterial), "detail/detailsprites_%s", mapDetailSprites);
		DispatchKeyValue(0, "detailmaterial", detailMaterial);
	}
	
	
	// Remove old Overlay
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "env_screenoverlay")) != -1) {
		AcceptEntityInput(ent, "Kill");
	}
	
	SetCommandFlags("r_screenoverlay", GetCommandFlags("r_screenoverlay") & ~FCVAR_CHEAT);
	for (ent = 1; ent <= MaxClients; ent++) {
		if (IsClientInGame(ent)) {
			ClientCommand(ent, "r_screenoverlay \"\"");
		}
	}
	SetCommandFlags("r_screenoverlay", GetCommandFlags("r_screenoverlay") | FCVAR_CHEAT);
	
	// Apply Overlay
	if (!StrEqual(mapOverlay, "")) {
		ent = CreateEntityByName("env_screenoverlay");
		
		if (IsValidEntity(ent)) {
			DispatchKeyValue(ent, "OverlayName1", mapOverlay);

			SetVariantString("OnUser1 !self,StartOverlays");
			AcceptEntityInput(ent, "AddOutput");

			SetVariantString("OnUser1 !self,FireUser1,,1");
			AcceptEntityInput(ent, "AddOutput");

			AcceptEntityInput(ent, "FireUser1");
		}
	}
	
	// Estimate Map Region
	if (mapEstimateRegion) {
		EstimateMapRegion();
	}
	
	// Init Color Correction
	if (!StrEqual(mapColorCorrection1, "")) {
		Format(mapColorCorrection1, sizeof(mapColorCorrection1), "materials/correction/%s", mapColorCorrection1);
	}
	
	if (!StrEqual(mapColorCorrection2, "")) {
		Format(mapColorCorrection2, sizeof(mapColorCorrection2), "materials/correction/%s", mapColorCorrection2);
	}
}

/* ApplySoundscape()
**
** Applies the Soundscape to the map.
** -------------------------------------------------------------------------- */
void ApplySoundscape()
{
	int ent = -1;
	int proxy = -1;
	int scape = -1;
	float org[3];
	char target[32];
	
	// Find all soundscape proxies and determine if they're inside or outside
	while ((ent = FindEntityByClassname(ent, "env_soundscape_proxy")) != -1) {
		proxy = GetEntPropEnt(ent, Prop_Data, "m_hProxySoundscape");
		
		if (proxy != -1) {
			GetEntPropString(proxy, Prop_Data, "m_iName", target, sizeof(target));
			
			if ((StrContains(target, "inside", false) != -1) || (StrContains(target, "indoor", false) != -1) ||
					(StrContains(target, "outside", false) != -1) || (StrContains(target, "outdoor", false) != -1)) {
				// Create soundscape using loaded attributes
				scape = CreateEntityByName("env_soundscape");

				if (IsValidEntity(scape)) {
					GetEntPropVector(ent, Prop_Data, "m_vecOrigin", org);
					TeleportEntity(scape, org, NULL_VECTOR, NULL_VECTOR);
					
					DispatchKeyValueFloat(scape, "radius", GetEntPropFloat(ent, Prop_Data, "m_flRadius"));
					
					if ((StrContains(target, "inside", false) != -1) || (StrContains(target, "indoor", false) != -1)) {
						DispatchKeyValue(scape, "soundscape", mapSoundscapeInside);
						DispatchKeyValue(scape, "targetname", mapSoundscapeInside);
					} else if ((StrContains(target, "outside", false) != -1) || (StrContains(target, "outdoor", false) != -1)) {
						DispatchKeyValue(scape, "soundscape", mapSoundscapeOutside);
						DispatchKeyValue(scape, "targetname", mapSoundscapeOutside);
					}
					
					DispatchSpawn(scape);
				}
			}
		}
		
		AcceptEntityInput(ent, "Kill");
	}
	
	// Do the same to normal soundscapes
	while ((ent = FindEntityByClassname(ent, "env_soundscape")) != -1) {
		GetEntPropString(ent, Prop_Data, "m_iName", target, sizeof(target));
		
		if (!StrEqual(target, mapSoundscapeInside) && !StrEqual(target, mapSoundscapeOutside)) {
			scape = CreateEntityByName("env_soundscape");
		
			if (IsValidEntity(scape)) {
				GetEntPropVector(ent, Prop_Data, "m_vecOrigin", org);
				TeleportEntity(scape, org, NULL_VECTOR, NULL_VECTOR);
				
				DispatchKeyValueFloat(scape, "radius", GetEntPropFloat(ent, Prop_Data, "m_flRadius"));
				
				if ((StrContains(target, "inside", false) != -1) || (StrContains(target, "indoor", false) != -1)) {
					DispatchKeyValue(scape, "soundscape", mapSoundscapeInside);
					DispatchKeyValue(scape, "targetname", mapSoundscapeInside);
				} else {
					DispatchKeyValue(scape, "soundscape", mapSoundscapeOutside);
					DispatchKeyValue(scape, "targetname", mapSoundscapeOutside);
				}
				
				DispatchSpawn(scape);
			}
		
			AcceptEntityInput(ent, "Kill");
		}
	}
}

/* ApplyConfigRound()
**
** Applys the loaded configuration to the current map. Not all attributes can be
** applied here. Some must be reapplied every round start.
** -------------------------------------------------------------------------- */
void ApplyConfigRound()
{
	int ent;
	char filename[96];
	
	// Apply No Particles
	if (mapNoParticles) {
		ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "info_particle_system")) != -1) {
			GetEntPropString(ent, Prop_Data, "m_iName", filename, sizeof(filename));
			
			if ((StrContains(filename, "particle_rain") != -1) ||
					(StrContains(filename, "particle_snow") != -1) ||
					(StrContains(filename, "particle_waterdrops") != -1)) {
				AcceptEntityInput(ent, "Kill");
			}
		}
	}
	
	// Apply Indoors
	if (mapIndoors) {
		if (StrEqual(mapParticle, "env_themes_rain") ||
				StrEqual(mapParticle, "env_themes_rain_light") ||
				StrEqual(mapParticle, "env_themes_snow") ||
				StrEqual(mapParticle, "env_themes_snow_light") ||
				StrEqual(mapParticle, "env_themes_leaves")) {
			StrCat(mapParticle, sizeof(mapParticle), "_noclip");
		}
	}
	
	// Apply Particles
	if (cvParticles.BoolValue) {
		CreateParticles();
	}
	
	// Apply Bloom
	if (mapBloom != -1.0) {
		ent = FindEntityByClassname(-1, "env_tonemap_controller");
		
		if (ent != -1) {
			SetVariantFloat(mapBloom);
			AcceptEntityInput(ent, "SetBloomScale");
		}
	}
	
	// Remove old Color Correction
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "color_correction")) != -1) {
		AcceptEntityInput(ent, "Kill");
	}
	
	// Apply Color Correction
	mapCCEntity1 = -1;
	if (!StrEqual(mapColorCorrection1, "")) {
		mapCCEntity1 = CreateEntityByName("color_correction");
		
		if (IsValidEntity(mapCCEntity1)) {
			DispatchKeyValue(mapCCEntity1, "maxweight", "1.0");
			DispatchKeyValue(mapCCEntity1, "maxfalloff", "-1");
			DispatchKeyValue(mapCCEntity1, "minfalloff", "0.0");
			DispatchKeyValue(mapCCEntity1, "filename", mapColorCorrection1);
			
			DispatchSpawn(mapCCEntity1);
			ActivateEntity(mapCCEntity1);
			AcceptEntityInput(mapCCEntity1, "Enable");
		}
	}
	
	mapCCEntity2 = -1;
	if (!StrEqual(mapColorCorrection2, "")) {
		mapCCEntity2 = CreateEntityByName("color_correction");
		
		if (IsValidEntity(mapCCEntity2)) {
			DispatchKeyValue(mapCCEntity2, "maxweight", "1.0");
			DispatchKeyValue(mapCCEntity2, "maxfalloff", "-1");
			DispatchKeyValue(mapCCEntity2, "minfalloff", "0.0");
			DispatchKeyValue(mapCCEntity2, "filename", mapColorCorrection2);
			
			DispatchSpawn(mapCCEntity2);
			ActivateEntity(mapCCEntity2);
			AcceptEntityInput(mapCCEntity2, "Enable");
		}
	}
	
	// Apply No Sun
	if (mapNoSun) {
		ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "env_sun")) != -1) {
			AcceptEntityInput(ent, "Kill");
		}
		
		ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "prop_dynamic")) != -1) {
			char model[128];
			
			GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
			
			if (StrEqual(model, "models/props_skybox/sunnoon.mdl")) {
				AcceptEntityInput(ent, "Kill");
			}
		}
	}
	
	// Apply Big Sun
	if (mapBigSun) {
		ent = CreateEntityByName("env_sun");
		
		if (IsValidEntity(ent)) {
			DispatchKeyValue(ent, "angles", "0 180 0");
			DispatchKeyValue(ent, "HDRColorScale", "2.0");
			DispatchKeyValue(ent, "material", "sprites/light_glow02_add_noz");
			DispatchKeyValue(ent, "overlaycolor", "57 73 87");
			DispatchKeyValue(ent, "overlaymaterial", "sprites/light_glow02_add_noz");
			DispatchKeyValue(ent, "overlaysize", "-1");
			DispatchKeyValue(ent, "pitch", "-45");
			DispatchKeyValue(ent, "rendercolor", "242 197 134");
			DispatchKeyValue(ent, "size", "100");
			DispatchKeyValue(ent, "use_angles", "1");
			
			DispatchSpawn(ent);
			ActivateEntity(ent);
			
			AcceptEntityInput(ent, "TurnOn");
		}
	}

	if(fishes != null) {
		int entity = -1;
		while((entity = FindEntityByClassname(entity, "func_fish_pool")) != -1) {
		#if defined CAN_GET_UTLVECTOR
			char name[32];
			GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));

			if(StrContains(name, "themes_fish_pool") != -1)
			{
				int len = GetEntPropArraySize(entity, Prop_Data, "m_fishes");
				for(int i = 0; i < len; ++i) {
					int fish = GetEntPropEnt(entity, Prop_Data, "m_fishes", i);
					RemoveEntity(fish);
				}
		#endif
				RemoveEntity(entity);
		#if defined CAN_GET_UTLVECTOR
			}
		#endif
		}

	#if !defined CAN_GET_UTLVECTOR
		entity = -1;
		while((entity = FindEntityByClassname(entity, "fish")) != -1) {
			RemoveEntity(entity);
		}
	#endif

		for(int i = 0; i < fishes.Length; ++i) {
			FishInfo info;
			fishes.GetArray(i, info, sizeof(info));

			entity = CreateEntityByName("func_fish_pool");
			DispatchKeyValue(entity, "targetname", "themes_fish_pool");
			SetEntPropString(entity, Prop_Data, "m_ModelName", info.model);
			SetEntPropFloat(entity, Prop_Data, "m_maxRange", info.range);
			SetEntProp(entity, Prop_Data, "m_fishCount", info.count);
			TeleportEntity(entity, info.pos);
			DispatchSpawn(entity);
		}
	}
}

/* CreateParticles()
**
** Creates particles around the map.
** -------------------------------------------------------------------------- */
void CreateParticles()
{
	if (!StrEqual(mapParticle, "")) {
		// Remove old particles
		int ent = -1;
		int num = 0;
		
		while ((ent = FindEntityByClassname(ent, "info_particle_system")) != -1) {
			if (IsValidEntity(ent)) {
				char name[32];
				
				GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
				
				if (StrContains(name, "themes_particle") != -1) {
					AcceptEntityInput(ent, "Kill");
				}
			}
		}

		/*ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "item_ammopack_full")) != -1) {
			if (IsValidEntity(ent)) {
				AcceptEntityInput(ent, "Kill");
			}
		}*/
		
		int x, y, nx, ny;
		float w, h, ox, oy;
		
		w = mapX2[currentStage] - mapX1[currentStage];
		h = mapY2[currentStage] - mapY1[currentStage];
		
		nx = RoundToFloor(w/1024.0) + 1;
		ny = RoundToFloor(h/1024.0) + 1;
		
		ox = (((RoundToFloor(w/1024.0) + 1) * 1024.0) - w)/2;
		oy = (((RoundToFloor(h/1024.0) + 1) * 1024.0) - h)/2;
		
		for (x = 0; x < nx; x++) {
			for (y = 0; y < ny; y++) {
				float pos[3];
				pos[0] = mapX1[currentStage] + x*1024.0 + 512.0 - ox;
				pos[1] = mapY1[currentStage] + y*1024.0 + 512.0 - oy;
				pos[2] = mapParticleHeight + mapZ[currentStage];

				int particle = CreateEntityByName("info_particle_system");

				// Check if it was created correctly
				if (IsValidEdict(particle)) {
					// Teleport, set up
					TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
					DispatchKeyValue(particle, "effect_name", mapParticle);
					DispatchKeyValue(particle, "targetname", "themes_particle");
					
					// Spawn and start
					DispatchSpawn(particle);
					ActivateEntity(particle);
					AcceptEntityInput(particle, "Start");
					
					/*ent = CreateEntityByName("item_ammopack_full");
					TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR);
					DispatchSpawn(ent);
					ActivateEntity(ent);*/
				}
				
				num++;
				
				if (num > 64) {
					LogMessage("Error: Too many particles!");
					return;
				}
			}
		}
		
		LogMessage("Current stage: %i", currentStage);
		LogMessage("Created %i particles of type %s", num, mapParticle);
	}
}

/* EstimateMapRegion()
**
** Estimates the region of the map by finding the minimum and maximum position
** of entities. Only used for particles.
** -------------------------------------------------------------------------- */
void EstimateMapRegion()
{
	if (!StrEqual(mapParticle, "")) {

		if(cvEstimateMethod.IntValue == 0) {
			int maxEnts = GetMaxEntities();
			
			for (int i = MaxClients + 1; i <= maxEnts; i++) {
				if (!IsValidEntity(i)) continue;
				
				char name[32];
				GetEntityNetClass(i, name, 32);
				
				if (HasEntProp(i, Prop_Send, "m_vecOrigin")) {
					float pos[3];
					GetEntPropVector(i, Prop_Send, "m_vecOrigin", pos);
					
					if (pos[0] < mapX1[0]) {
						mapX1[0] = pos[0];
					}
					if (pos[0] > mapX2[0]) {
						mapX2[0] = pos[0];
					}
					
					if (pos[1] < mapY1[0]) {
						mapY1[0] = pos[1];
					}
					if (pos[1] > mapY2[0]) {
						mapY2[0] = pos[1];
					}
				}
			}

			mapZ[0] = 0.0;
		} else {
			float m_WorldMins[3];
			GetEntPropVector(0, Prop_Send, "m_WorldMins", m_WorldMins);

			float m_WorldMaxs[3];
			GetEntPropVector(0, Prop_Send, "m_WorldMaxs", m_WorldMaxs);

			mapX1[0] = m_WorldMins[0];
			mapX2[0] = m_WorldMaxs[0];
			mapY1[0] = m_WorldMins[2];
			mapY2[0] = m_WorldMaxs[2];

			mapZ[0] = m_WorldMaxs[1];
		}
		
		for (int i = 1; i < MAX_STAGES; i++) {
			mapX1[i] = mapX1[0];
			mapX2[i] = mapX2[0];
			mapY1[i] = mapY1[0];
			mapY2[i] = mapY2[0];
			mapZ[i] = mapZ[0];
		}
		
		LogMessage("Map region estimated: (%f, %f) to (%f, %f) [%f x %f], z = %f", mapX1[0], mapY1[0], mapX2[0], mapY2[0], mapX2[0] - mapX1[0], mapY2[0] - mapY1[0], mapZ[0]);
	}
}

/* LogTheme()
**
** Prints all of the current theme's attributes.
** -------------------------------------------------------------------------- */
void LogTheme()
{
	LogMessage("Loaded theme: %s", mapTheme);
	
	#if defined DEBUG
	LogMessage("Skybox: %s", mapSkybox);
	LogMessage("Skybox Fog Color: %d", mapSkyboxFogColor);
	LogMessage("Skybox Fog Start: %f", mapSkyboxFogStart);
	LogMessage("Skybox Fog End: %f", mapSkyboxFogEnd);
	
	LogMessage("Fog Color: %s", mapFogColor);
	LogMessage("Fog Start: %f", mapFogStart);
	LogMessage("Fog End: %f", mapFogEnd);
	LogMessage("Fog Density: %f", mapFogDensity);	
	
	LogMessage("Particles: %s", mapParticle);
	LogMessage("Particle Height: %f", mapParticleHeight);
	
	LogMessage("Soundscape Inside: %s", mapSoundscapeInside);
	LogMessage("Soundscape Outside: %s", mapSoundscapeOutside);
	
	LogMessage("Lighting: %s", mapLighting);
	LogMessage("Bloom: %f", mapBloom);
	LogMessage("Color Correction 1: %s", mapColorCorrection1);
	LogMessage("Color Correction 2: %s", mapColorCorrection2);
	
	LogMessage("Detail Sprites: %s", mapDetailSprites);
	LogMessage("No Sun: %d", mapNoSun);
	LogMessage("Big Sun: %d", mapBigSun);
	LogMessage("No Particles: %d", mapNoParticles);
	LogMessage("Indoors: %d", mapIndoors);
	LogMessage("Overlay: %s", mapOverlay);
	#endif
}

/* Event_RoundEnd()
**
** When a round ends.
** -------------------------------------------------------------------------- */
Action Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	if (pluginEnabled) {
		// Check if a full round has completed
		if (GetEventInt(event, "full_round")) {
			currentStage = 0;
		} else if (currentStage < numStages - 1) {
			currentStage++;
		}
	}
	
	return Plugin_Continue;
}

/* Event_RoundStart()
**
** When a round starts.
** -------------------------------------------------------------------------- */
Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if (pluginEnabled) {
		// Need to wait at least 0.2 before bloom is able to be set
		// Increased delay as possible fix for CC and particles
		CreateTimer(2.0, Timer_RoundStart);
	}
	
	return Plugin_Continue;
}

/* Timer_RoundStart()
**
** Timer for round start.
** ------------------------------------------------------------------------- */
Action Timer_RoundStart(Handle timer, any data)
{
	ApplyConfigRound();
	
	AnnounceTheme();

	return Plugin_Continue;
}

/* Event_PlayerTeam()
**
** When a player joins a team.
** -------------------------------------------------------------------------- */
Action Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
	if (pluginEnabled) {
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		
		if (client && IsClientInGame(client)) {
			// Apply Skybox Fog Color
			if (mapSkyboxFogColor != -1) {
				SetEntProp(client, Prop_Send, "m_skybox3d.fog.enable", 1);
				SetEntProp(client, Prop_Send, "m_skybox3d.fog.colorPrimary", mapSkyboxFogColor);
				SetEntProp(client, Prop_Send, "m_skybox3d.fog.colorSecondary", mapSkyboxFogColor);
			}
			
			// Apply Skybox Fog Start
			if (mapSkyboxFogStart != -1.0) {
				SetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.start", mapSkyboxFogStart);
			}
			
			// Apply Skybox Fog End
			if (mapSkyboxFogEnd != -1.0) {
				SetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.end", mapSkyboxFogEnd);
			}
		}
	}
	
	return Plugin_Continue;
}

/* AnnounceTheme()
**
** Announces the current theme.
** -------------------------------------------------------------------------- */
void AnnounceTheme()
{
	if (cvAnnounce.BoolValue) {
		CPrintToChatAll("%t", "Announce_Theme", mapTag, mapTheme);
	}
}

/* StringToTimeOfDay()
**
** Converts a string representation of a time of day into an integer.
** -------------------------------------------------------------------------- */
int StringToTimeOfDay(char time[6])
{
	int hours = 0;
	int minutes = 0;
	char buffers[2][4];
	
	int num = ExplodeString(time, ":", buffers, 3, 4);
	
	if (num > 0) {
		hours = StringToInt(buffers[0]) - GetTimezoneHourOffset();
		
		if (num > 1) {
			minutes = StringToInt(buffers[1]) - GetTimezoneMinuteOffset();
		}
	}
	
	if (minutes < 0) {
		minutes += 60;
		hours -= 1;
	}
	
	if (hours < 0) {
		hours += 24;
	}
	
	return hours * 60 * 60 + minutes * 60;
}

/* GetTimeOfDay()
**
** Returns an integer storing the current time of day (hours and minutes only.)
** -------------------------------------------------------------------------- */
int GetTimeOfDay()
{
	int result = GetTime();
	
	result %= 86400;
	result -= result % 60;
	
	return result;
}

/* GetTimezoneHourOffset()
**
** Returns the hour offset for the server's current timezone.
** -------------------------------------------------------------------------- */
int GetTimezoneHourOffset()
{
	char temp[3];
	FormatTime(temp, sizeof(temp), "%H", 0);
	
	return StringToInt(temp);
}

/* GetTimezoneMinuteOffset()
**
** Returns the minute offset for the server's current timezone.
** -------------------------------------------------------------------------- */
int GetTimezoneMinuteOffset()
{
	char temp[3];
	FormatTime(temp, sizeof(temp), "%M", 0);
	
	return StringToInt(temp);
}

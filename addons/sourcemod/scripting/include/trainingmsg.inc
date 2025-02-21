#if defined trainingmsg_inc
	#endinput
#endif
#define trainingmsg_inc

#define TRAINING_MSG_MAX_WIDTH 43
#define TRAINING_MSG_MAX_HEIGHT 4

enum TrainingMsgMenuAction
{
	TrainingMsgMenuAction_Select,
	TrainingMsgMenuAction_Cancel,
};

enum
{
	TrainingMsgMenuCancel_Disconnected,
	TrainingMsgMenuCancel_Interrupted,
	TrainingMsgMenuCancel_Exit,
	TrainingMsgMenuCancel_Timeout,
};

typedef TrainingMsgMenuHandler = function void (TrainingMsgMenuAction action, int client, int param1, any data);

#define TRAININGMSGMENU_TIME_FOREVER 0

methodmap TrainingMsgMenu
{
	public native TrainingMsgMenu(TrainingMsgMenuHandler handler);

	public native void SetTitle(const char[] str);

	public native bool DrawItem(const char[] str);
	public native bool AddItem(const char[] str, any data = 0);

	property bool ExitButton {
		public native set(bool value);
	}

	public native bool SendToClient(int client, int time);
	//public native void SendToAll(int time);
	//public native void SendToClients(const int[] clients, int numClients, int time);
};

native bool IsTrainingMessageVisibleToClient(int client);
native bool IsTrainingMessageVisibleToAll();

/*
if you want text to be hinted use \x2 before the text and \x1 after like this
Format(mytext, sizeof(mytext), "\x2this text is hinted \x1now this text isnt");
*/

native void SendTrainingMessageToClients(const int[] clients, int numClients, const char[] title, const char[] msg);
native void SendTrainingMessageToAll(const char[] title, const char[] msg);
native void SendTrainingMessageToClient(int client, const char[] title, const char[] msg);

native void RemoveTrainingMessageFromAll();
native void RemoveTrainingMessageFromClients(const int[] clients, int numClients);

native void ChangeTrainingMessageTitleClients(const int[] clients, int numClients, const char[] title);
native void ChangeTrainingMessageTextClients(const int[] clients, int numClients, const char[] title);

native void ChangeTrainingMessageTitleAll(const char[] title);
native void ChangeTrainingMessageTextAll(const char[] title);

stock void RemoveTrainingMessageFromClient(int client)
{
	int clients[1];
	clients[0] = client;

	RemoveTrainingMessageFromClients(clients, sizeof(clients));
}

stock void ChangeTrainingMessageTitleClient(int client, const char[] title)
{
	int clients[1];
	clients[0] = client;

	ChangeTrainingMessageTitleClients(clients, sizeof(clients), title);
}

stock void ChangeTrainingMessageTextClient(int client, const char[] title)
{
	int clients[1];
	clients[0] = client;

	ChangeTrainingMessageTextClients(clients, sizeof(clients), title);
}

public SharedPlugin __pl_trainingmsg =
{
	name = "trainingmsg",
	file = "trainingmsg.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_trainingmsg_SetNTVOptional()
{
	
}
#endif
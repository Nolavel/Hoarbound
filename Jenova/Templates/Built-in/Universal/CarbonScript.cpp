
/* Jenova Carbon C++ Script (Meteora) */

// Godot SDK
#include <Godot/godot.hpp>
#include <Godot/classes/$BASE_TYPE_HEADER$>

// Namespaces
using namespace godot;
using namespace jenova::sdk;

// Enable Carbon Mode
JENOVA_CARBON_SCRIPT

// $BASE_CLASS_NAME$ Implementation
class $BASE_CLASS_NAME$ : public $BASE_TYPE$, public CarbonScript<$BASE_TYPE$>
{
public:
	// Routines
	void OnAwake()
	{
		// Called when Node enters SceneTree
	}
	void OnDestroy()
	{
		// Called when Node exits SceneTree
	}
	void OnReady()
	{
		// Called when Node and all of its children entered SceneTree
	}
	void OnProcess(double delta)
	{
		// Called on every frame
	}

public:
	// Define Public Methods Here
	
private:
	// Define Internal Methods Here
	
public:
	// Define Properties Here
	
private:
	// Define Internal Variables Here

};

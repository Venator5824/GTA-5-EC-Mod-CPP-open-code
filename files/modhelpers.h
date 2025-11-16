// ModHelpers.h v1.0.14
// (Bereinigt, enthält nur noch ApplyNpcTasks)
#pragma once
#include "main.h" 
#include "types.h"
#include <string>
#include "natives.h"


/**
 * @brief Forces the NPC to stop current tasks and face the player for conversation.
 */
void ApplyNpcTasks(Ped npc, Ped player);


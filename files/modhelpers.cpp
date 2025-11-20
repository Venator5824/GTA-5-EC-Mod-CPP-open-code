// ModHelpers.cpp v1.0.15 (Modular-Update-Fix)
#define _CRT_SECURE_NO_WARNINGS

#include "ModHelpers.h"
#include "natives.h"
#include "types.h"
#include "main.h" 
#include <fstream> 
#include <chrono> 
#include <iomanip> 
#include <ctime>
#include <string> 

/**
 * @brief Schreibt eine Nachricht in die Log-Datei mit Zeitstempel.
 */
void LogHelpers(const std::string& message) {
    auto now = std::chrono::system_clock::now();
    auto now_c = std::chrono::system_clock::to_time_t(now);
    std::ofstream log("kkamel.log", std::ios_base::app);
    if (log.is_open()) {
        log << "[" << std::put_time(std::localtime(&now_c), "%Y-%m-%d %H:%M:%S") << "] [ModHelpers] " << message << "\n";
        log.flush();
    }
}

/**
 * @brief NEU: "Schwere" Funktion, die nur EINMAL beim Start der Konversation aufgerufen wird.
 * Enthält Task-Clearing und WAITs.
 */
void StartNpcConversationTasks(Ped npc, Ped player) {
    LogHelpers("StartNpcConversationTasks: Initializing NPC=" + std::to_string(npc));
    if (!ENTITY::DOES_ENTITY_EXIST(npc)) {
        LogHelpers("StartNpcConversationTasks: NPC does not exist");
        return;
    }

    LogHelpers("StartNpcConversationTasks: Clearing NPC tasks IMMEDIATELY");
    AI::CLEAR_PED_TASKS_IMMEDIATELY(npc);

    // Warte kurz, damit der Ped die Task-Löschung verarbeiten kann
    SYSTEM::WAIT(50);

    LogHelpers("StartNpcConversationTasks: Setting NPC to face player");
    AI::TASK_TURN_PED_TO_FACE_ENTITY(npc, player, -1);

    SYSTEM::WAIT(50);

    LogHelpers("StartNpcConversationTasks: Setting NPC to stand still");
    AI::TASK_STAND_STILL(npc, -1);

    LogHelpers("StartNpcConversationTasks: Setting PED config flag 281 (Allows turning head)");
    PED::SET_PED_CONFIG_FLAG(npc, 281, TRUE);

    LogHelpers("StartNpcConversationTasks: Initial tasks applied");
}

/**
 * @brief NEU: "Leichte" Funktion, die in JEDEM FRAME (aus Sektion 2) aufgerufen wird.
 * Hält den NPC fest. Enthält KEINE WAIT-Befehle.
 */
void UpdateNpcConversationTasks(Ped npc, Ped player) {
    if (!ENTITY::DOES_ENTITY_EXIST(npc)) {
        return;
    }

    // Diese Befehle sind "leicht" und MÜSSEN jeden Frame laufen, 
    // um die native KI zu überschreiben, die den Ped weglaufen lässt.
    AI::TASK_STAND_STILL(npc, -1);
    AI::TASK_TURN_PED_TO_FACE_ENTITY(npc, player, -1);

    // TODO: Hier kannst du später deine Gesten- und Animationslogik einfügen,
    // z.B. if (g_is_npc_speaking) { AI::PLAY_FACIAL_ANIM(...) }
}

// EOF

#include <unordered_map>
#include <mutex>
#include "main.h"
#include "ConversationSystem.h"
#include "AbstractCalls.h"
#include "EntityRegistry.h"


using namespace AbstractGame;
using namespace AbstractTypes;

// --- STORAGE ---
static std::unordered_map<ChatID, ConversationData> g_activeChats;
static std::unordered_map<ChatID, ConversationData> g_archivedChats;
static std::unordered_map<PersistID, ChatID> g_participantToChatMap;
static std::unordered_map<uint64_t, std::string> g_historyIndex;

// --- THREAD SAFETY ---
static std::shared_mutex g_convoMutex;
static std::mutex g_idGenMutex;

// --- HELPERS ---
inline uint64_t MakePairKey(PersistID p1, PersistID p2) {
    if (p1 > p2) std::swap(p1, p2);
    return p1 ^ (p2 + 0x9e3779b9 + (p1 << 6) + (p1 >> 2));
}

// --- ID LOGIC ---
PersistID ConvoManager::GetPersistIDForHandle(GameHandle handle) {
    return EntityRegistry::RegisterNPC(handle);
}

ChatID ConvoManager::GenerateNewChatID() {
    static ChatID counter = 100;
    std::lock_guard<std::mutex> lock(g_idGenMutex);
    return counter++;
}

// --- LIFECYCLE ---
ChatID ConvoManager::InitiateConversation(GameHandle initiator, GameHandle target, ChatID forceID) {
    std::unique_lock<std::shared_mutex> lock(g_convoMutex);

    PersistID p1 = GetPersistIDForHandle(initiator);
    PersistID p2 = GetPersistIDForHandle(target);

    ChatID newID;
    if (forceID != 0) {
        if (g_activeChats.count(forceID)) return forceID;
        newID = forceID;
    }
    else {
        newID = GenerateNewChatID();
    }

    ConversationData data;
    data.chatID = newID;
    data.participants.push_back(p1);
    data.participants.push_back(p2);
    data.timestamp = GetTimeMs();
    data.isActive = true;

    // Load Memory
    uint64_t pairKey = MakePairKey(p1, p2);
    if (g_historyIndex.count(pairKey)) {
        data.history.push_back("<|system|>\n[MEMORY] Previous encounter: " + g_historyIndex[pairKey]);
    }

    g_activeChats[newID] = data;
    g_participantToChatMap[p1] = newID;
    g_participantToChatMap[p2] = newID;

    return newID;
}

void ConvoManager::CloseConversation(ChatID chatID) {
    std::unique_lock<std::shared_mutex> lock(g_convoMutex);

    auto it = g_activeChats.find(chatID);
    if (it != g_activeChats.end()) {
        ConversationData& data = it->second;
        data.isActive = false;

        // Save Summary
        if (!data.summary.empty() && data.participants.size() >= 2) {
            uint64_t pairKey = MakePairKey(data.participants[0], data.participants[1]);
            g_historyIndex[pairKey] = data.summary;
        }

        // Cleanup
        for (auto p : data.participants) {
            g_participantToChatMap.erase(p);
        }

        g_archivedChats[chatID] = data;
        g_activeChats.erase(it);
    }
}

// --- DATA ACCESS ---
ChatID ConvoManager::GetActiveChatID(GameHandle handle) {
    std::shared_lock<std::shared_mutex> lock(g_convoMutex);
    PersistID targetPid = GetPersistIDForHandle(handle);

    auto it = g_participantToChatMap.find(targetPid);
    if (it != g_participantToChatMap.end()) {
        return it->second;
    }
    return 0;
}

void ConvoManager::AddMessageToChat(ChatID chatID, const std::string& senderName, const std::string& message) {
    std::unique_lock<std::shared_mutex> lock(g_convoMutex);

    auto it = g_activeChats.find(chatID);
    if (it != g_activeChats.end()) {
        std::string entry;
        if (senderName == "Player") entry = "<|user|>\n" + message;
        else entry = "<|assistant|>\n" + message;
        it->second.history.push_back(entry);

        // --- SAFETY LIMIT (ADDED) ---
        // Prevents crashes if Optimizer is OFF or slow
        int hardLimit = ConfigReader::g_Settings.MaxChatHistoryLines;
        if (hardLimit < 5) hardLimit = 10; // Safety floor

        // Allow +5 buffer for optimizer to catch up before hard delete
        if (it->second.history.size() > (size_t)(hardLimit + 5)) {
            // Delete oldest message (Index 1) to preserve System Prompt (Index 0)
            if (it->second.history.size() > 1) {
                it->second.history.erase(it->second.history.begin() + 1);
            }
        }
    }
}

void ConvoManager::SetConversationSummary(ChatID chatID, const std::string& summary) {
    std::unique_lock<std::shared_mutex> lock(g_convoMutex);
    auto it = g_activeChats.find(chatID);
    if (it != g_activeChats.end()) {
        it->second.summary = summary;
    }
}

void ConvoManager::ReplaceHistory(ChatID chatID, const std::vector<std::string>& newHistory) {
    std::unique_lock<std::shared_mutex> lock(g_convoMutex);
    auto it = g_activeChats.find(chatID);
    if (it != g_activeChats.end()) {
        it->second.history = newHistory;
    }
}

std::vector<std::string> ConvoManager::GetChatHistory(ChatID chatID) {
    std::shared_lock<std::shared_mutex> lock(g_convoMutex);
    auto it = g_activeChats.find(chatID);
    if (it != g_activeChats.end()) {
        return it->second.history;
    }
    return {};
}

std::string ConvoManager::GetLastSummaryBetween(PersistID p1, PersistID p2) {
    std::shared_lock<std::shared_mutex> lock(g_convoMutex);
    uint64_t pairKey = MakePairKey(p1, p2);
    if (g_historyIndex.count(pairKey)) {
        return g_historyIndex[pairKey];
    }
    return "";
}

bool ConvoManager::IsChatActive(ChatID chatID) {
    std::shared_lock<std::shared_mutex> lock(g_convoMutex);
    auto it = g_activeChats.find(chatID);
    return (it != g_activeChats.end() && it->second.isActive);
}

void ConvoManager::SetChatContext(ChatID chatID, const std::string& location, const std::string& weather) {
    std::unique_lock<std::shared_mutex> lock(g_convoMutex);
    auto it = g_activeChats.find(chatID);
    if (it != g_activeChats.end()) {
        it->second.cd_location = location;
        it->second.cd_weather = weather;
    }
}
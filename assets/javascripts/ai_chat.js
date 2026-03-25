// AI Chat Initialisierung
(function() {
  'use strict';
  
  function initAIChat() {
    console.log('AI Chat Initialisierung gestartet');
    
    // Stelle sicher, dass die Sidebar existiert
    const sidebar = document.querySelector('#sidebar');
    if (!sidebar) {
      console.log('Sidebar nicht gefunden, versuche es später erneut');
      setTimeout(initAIChat, 1000);
      return;
    }
    
    // Prüfe, ob wir uns auf einer Issue-Seite befinden
    const issueMatch = window.location.pathname.match(/\/issues\/(\d+)/);
    if (!issueMatch) {
      console.log('Keine Issue-Seite gefunden');
      return;
    }
    
    const issueId = issueMatch[1];
    console.log('Issue ID gefunden:', issueId);
    
    // Erstelle das Chat-Container-Element, falls es noch nicht existiert
    let chatContainer = document.getElementById('ai-chat-sidebar');
    if (!chatContainer) {
      console.log('Erstelle Chat-Container');
      chatContainer = document.createElement('div');
      chatContainer.id = 'ai-chat-sidebar';
      chatContainer.className = 'ai-chat-container';
      chatContainer.innerHTML = `
        <h3>🤖 KI-Assistent</h3>
        <div class="ai-chat-messages" id="ai-chat-messages">
          <div class="ai-chat-welcome">
            <p>Stellen Sie Fragen zu diesem Ticket. Ich analysiere alle Kommentare und Informationen für Sie.</p>
          </div>
        </div>
        
        <div class="ai-chat-input-container">
          <textarea id="ai-chat-input" placeholder="Frage stellen..." rows="2"></textarea>
          <button id="ai-chat-send" class="button ai-chat-send-btn">
            <span>Fragen</span>
          </button>
        </div>
        
        <div id="ai-chat-loading" class="ai-chat-loading" style="display: none;">
          <span class="ai-chat-spinner"></span>
          <span>Analysiere...</span>
        </div>
      `;
      
      // Füge den Container am Ende der Sidebar hinzu
      sidebar.appendChild(chatContainer);
    }
    
    // Initialisiere das Chat-Verhalten
    initializeChatBehavior(issueId);
  }
  
  function initializeChatBehavior(issueId) {
    console.log('Initialisiere Chat-Verhalten für Issue:', issueId);
    
    let isLoading = false;
    
    function setupEventListeners() {
      const sendBtn = document.getElementById('ai-chat-send');
      const input = document.getElementById('ai-chat-input');
      
      if (sendBtn) {
        sendBtn.addEventListener('click', sendMessage);
      }
      
      if (input) {
        input.addEventListener('keypress', function(e) {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
          }
        });
      }
    }
    
    function sendMessage() {
      const input = document.getElementById('ai-chat-input');
      const question = input.value.trim();
      
      if (!question || isLoading) return;
      
      // Füge Frage zur Anzeige hinzu
      addMessageToChat('user', question);
      input.value = '';
      
      // Zeige Lade-Indikator
      showLoading(true);
      
      // Sende Anfrage
      const formData = new FormData();
      formData.append('issue_id', issueId);
      formData.append('question', question);
      
      fetch('/ai_chat/ask', {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': getCSRFToken()
        }
      })
      .then(response => response.json())
      .then(data => {
        showLoading(false);
        
        if (data.error) {
          addMessageToChat('error', 'Fehler: ' + data.error);
        } else {
          addMessageToChat('ai', data.answer, data.journal_references);
        }
      })
      .catch(error => {
        showLoading(false);
        addMessageToChat('error', 'Fehler: ' + error.message);
      });
    }
    
    function addMessageToChat(sender, content, journalReferences = []) {
      const messagesContainer = document.getElementById('ai-chat-messages');
      const welcomeMsg = messagesContainer.querySelector('.ai-chat-welcome');
      
      // Entferne Willkommensnachricht beim ersten Mal
      if (welcomeMsg && sender === 'user') {
        welcomeMsg.remove();
      }
      
      const messageDiv = document.createElement('div');
      messageDiv.className = `ai-chat-message ai-chat-${sender}`;
      
      const contentDiv = document.createElement('div');
      contentDiv.className = 'ai-chat-content';
      contentDiv.innerHTML = content; // HTML erlaubt für Links
      
      messageDiv.appendChild(contentDiv);
      
      // Füge Zeitstempel hinzu
      const timeDiv = document.createElement('div');
      timeDiv.className = 'ai-chat-time';
      timeDiv.textContent = new Date().toLocaleTimeString();
      messageDiv.appendChild(timeDiv);
      
      messagesContainer.appendChild(messageDiv);
      
      // Scrolle nach unten
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
      
      // Füge Event-Listener für Journal-Links hinzu
      setupJournalLinks(contentDiv);
    }
    
    function setupJournalLinks(container) {
      const links = container.querySelectorAll('.ai-journal-link');
      links.forEach(link => {
        link.addEventListener('click', function(e) {
          e.preventDefault();
          const journalId = this.dataset.journalId;
          scrollToJournal(journalId);
        });
      });
    }
    
    function scrollToJournal(journalId) {
      const journalElement = document.querySelector(`#change-${journalId}`);
      if (journalElement) {
        journalElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
        // Hebe das Element kurz hervor
        journalElement.style.backgroundColor = '#fffacd';
        setTimeout(() => {
          journalElement.style.backgroundColor = '';
        }, 2000);
      }
    }
    
    function showLoading(show) {
      isLoading = show;
      const loadingDiv = document.getElementById('ai-chat-loading');
      const sendBtn = document.getElementById('ai-chat-send');
      const input = document.getElementById('ai-chat-input');
      
      if (loadingDiv) {
        loadingDiv.style.display = show ? 'flex' : 'none';
      }
      
      if (sendBtn) {
        sendBtn.disabled = show;
        sendBtn.classList.toggle('ai-chat-disabled', show);
      }
      
      if (input) {
        input.disabled = show;
      }
    }
    
    function loadChatHistory() {
      fetch(`/ai_chat/history?issue_id=${issueId}`, {
        method: 'GET',
        headers: {
          'X-CSRF-Token': getCSRFToken()
        }
      })
      .then(response => response.json())
      .then(data => {
        if (data.messages && data.messages.length > 0) {
          // Entferne Willkommensnachricht
          const welcomeMsg = document.querySelector('.ai-chat-welcome');
          if (welcomeMsg) {
            welcomeMsg.remove();
          }
          
          // Zeige Historie
          data.messages.forEach(msg => {
            addMessageToChat('user', msg.question);
            addMessageToChat('ai', msg.answer, msg.journal_references);
          });
        }
      })
      .catch(error => {
        console.error('Fehler beim Laden des Chat-Verlaufs:', error);
      });
    }
    
    function getCSRFToken() {
      const token = document.querySelector('meta[name="csrf-token"]');
      return token ? token.getAttribute('content') : '';
    }
    
    // Initialisiere Event-Listener und lade Historie
    setupEventListeners();
    loadChatHistory();
  }
  
  // Warte bis das DOM vollständig geladen ist
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAIChat);
  } else {
    // DOM ist bereits geladen, aber vielleicht ist die Sidebar noch nicht da
    setTimeout(initAIChat, 500);
  }
  
  // Fallback: Versuche es erneut, wenn die Seite vollständig geladen ist
  window.addEventListener('load', function() {
    setTimeout(initAIChat, 1000);
  });
})();
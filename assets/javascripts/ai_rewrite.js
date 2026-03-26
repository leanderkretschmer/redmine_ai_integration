(function() {
  'use strict';

  // Map zum Speichern von Session-Daten pro Textarea
  const textareaSessions = new Map();

  // Session-Daten für eine Textarea abrufen oder initialisieren
  function getSessionData(textarea) {
    if (!textareaSessions.has(textarea)) {
      textareaSessions.set(textarea, {
        sessionId: null,
        versionId: null,
        versionHistory: {
          canGoPrev: false,
          canGoNext: false
        }
      });
    }
    return textareaSessions.get(textarea);
  }

  // Session-ID generieren
  function generateSessionId() {
    return 'session_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  // AI-Buttons erstellen (neue Version mit Korrektur und komplexen Buttons)
  function createAIButtons(textarea) {
    // Prüfen ob Buttons bereits existieren
    if (textarea.parentNode.querySelector('.ai-buttons-container')) {
      return;
    }

    // Initialisiere Session-Daten für dieses Feld
    const sessionData = getSessionData(textarea);

    const buttonContainer = document.createElement('div');
    buttonContainer.className = 'ai-buttons-container';

    const buttonGroup = document.createElement('div');
    buttonGroup.className = 'ai-button-group';

    // Korrektur Button (neu)
    const correctionButton = document.createElement('a');
    correctionButton.href = 'javascript:void(0)';
    correctionButton.className = 'ai-action-btn ai-correction-button';
    correctionButton.innerHTML = '<span class="icon icon-magic-wand"></span><span class="btn-text">Korrektur</span>';
    correctionButton.title = 'Automatische Korrektur oder Ausführung von Anweisungen im Text';

    // Komplexe Anfrage Button (neu)
    const complexButton = document.createElement('a');
    complexButton.href = 'javascript:void(0)';
    complexButton.className = 'ai-action-btn ai-complex-button';
    complexButton.innerHTML = '<svg class="icon icon-edit-svg"><use xlink:href="/assets/icons-35b4b65e.svg#icon--edit"></use></svg><span class="btn-text">Erweitern</span>';
    complexButton.title = 'Komplexe Anfrage mit zusätzlicher Anweisung';

    // Navigation Buttons (wie vorher)
    const prevButton = document.createElement('button');
    prevButton.type = 'button';
    prevButton.className = 'ai-prev-button button';
    prevButton.innerHTML = '&lt;';
    prevButton.style.display = 'none';
    prevButton.title = 'Vorherige Version';

    const nextButton = document.createElement('button');
    nextButton.type = 'button';
    nextButton.className = 'ai-next-button button';
    nextButton.innerHTML = '&gt;';
    nextButton.style.display = 'none';
    nextButton.title = 'Nächste Version';

    // Versionsauswahl (Dropdown)
    const versionSelect = document.createElement('select');
    versionSelect.className = 'ai-version-select';
    versionSelect.style.display = 'none';
    versionSelect.title = 'Version auswählen';

    // Komplexe Anfrage Input (neu)
    const complexInput = document.createElement('input');
    complexInput.type = 'text';
    complexInput.className = 'ai-complex-input';
    complexInput.placeholder = 'z.B. "Fülle die Tabelle aus" oder "Erweitere die Beschreibung"...';
    complexInput.style.display = 'none';

    buttonGroup.appendChild(correctionButton);
    buttonGroup.appendChild(complexButton);
    buttonGroup.appendChild(prevButton);
    buttonGroup.appendChild(nextButton);
    buttonGroup.appendChild(versionSelect);

    buttonContainer.appendChild(buttonGroup);
    buttonContainer.appendChild(complexInput);

    textarea.parentNode.insertBefore(buttonContainer, textarea.nextSibling);

    // Event Listener für neue Buttons
    correctionButton.addEventListener('click', function() {
      handleCorrection(textarea, correctionButton, prevButton, nextButton);
    });

    complexButton.addEventListener('click', function() {
      handleComplexRequest(textarea, complexButton, complexInput, prevButton, nextButton);
    });

    prevButton.addEventListener('click', function() {
      handleNavigateVersion(textarea, 'prev', prevButton, nextButton);
    });

    nextButton.addEventListener('click', function() {
      handleNavigateVersion(textarea, 'next', prevButton, nextButton);
    });

    versionSelect.addEventListener('change', function() {
      const selectedVersionId = versionSelect.value;
      if (!selectedVersionId) return;
      handleNavigateExactVersion(textarea, selectedVersionId, prevButton, nextButton);
    });

    // Beim Laden prüfen, ob bereits Versionen existieren
    checkExistingVersions(textarea, prevButton, nextButton).then(function(hasVersions){
      if (hasVersions) {
        populateVersionSelect(versionSelect, textarea);
      }
    });
  }

  // Korrektur-Funktion (neu)
  function handleCorrection(textarea, correctionButton, prevButton, nextButton) {
    const originalText = textarea.value.trim();
    if (!originalText) {
      alert('Bitte geben Sie zuerst einen Text ein.');
      return;
    }

    // Hole Slim Response Setting
    const settings = window.redmineAISettings || {};
    const isSlimResponse = settings.slim_response === '1';
    
    let systemPrompt = 'Analysiere den bereitgestellten Text. Falls der Text am Anfang eine klare Anweisung enthält (z. B. "korrigiere...", "fasse zusammen...", "übersetze..."), führe diese Anweisung für den restlichen Teil des Textes aus. Falls keine klare Anweisung am Anfang steht, führe eine allgemeine Korrektur von Rechtschreibung, Grammatik und Stil durch. Behalte den ursprünglichen Sinn bei.';
    
    if (isSlimResponse) {
      systemPrompt += ' Antworte ausschließlich mit dem bearbeiteten Text, ohne jegliche Erklärungen oder einleitende Sätze.';
    }

    handleAIRequest(textarea, correctionButton, prevButton, nextButton, originalText, systemPrompt, 'correction');
  }

  // Komplexe Anfrage Funktion (neu)
  function handleComplexRequest(textarea, complexButton, complexInput, prevButton, nextButton) {
    const originalText = textarea.value.trim();
    const userInstruction = complexInput.value.trim();
    
    if (!originalText) {
      alert('Bitte geben Sie zuerst einen Text ein.');
      return;
    }
    
    if (!userInstruction) {
      // Zeige Input-Feld an wenn noch nicht sichtbar
      complexInput.style.display = 'block';
      complexInput.focus();
      return;
    }

    const systemPrompt = `Führe folgende Anweisung aus: "${userInstruction}". Falls der Text am Anfang eine weitere klare Anweisung enthält, kombiniere beide Anweisungen. Antworte ausschließlich mit dem bearbeiteten Text, ohne jegliche Erklärungen oder einleitende Sätze.`;
    
    handleAIRequest(textarea, complexButton, prevButton, nextButton, originalText, systemPrompt, 'complex');
    
    // Verstecke Input wieder
    complexInput.style.display = 'none';
    complexInput.value = '';
  }

  // Generische AI-Anfrage Funktion
  function handleAIRequest(textarea, button, prevButton, nextButton, originalText, systemPrompt, requestType) {
    const issueId = extractIssueIdFromUrl();
    const journalId = extractJournalId(textarea);
    const fieldType = detectFieldType(textarea);
    const sessionData = getSessionData(textarea);
    
    if (!sessionData.sessionId) {
      sessionData.sessionId = generateSessionId();
    }

    // Speichere Original-Version wenn noch nicht vorhanden
    if (!sessionData.versionId) {
      ensureOriginalVersionSaved(originalText, sessionData.sessionId, fieldType, issueId, journalId);
    }

    // Hole Settings
    const settings = window.redmineAISettings || {};
    const provider = settings.ai_provider || 'openai';

    // Button-Status setzen
    setButtonLoading(button, true);

    handleStandardRequest(textarea, button, prevButton, nextButton, originalText, systemPrompt, sessionData, fieldType, issueId, journalId, provider, requestType);
  }

  function handleStandardRequest(textarea, button, prevButton, nextButton, originalText, systemPrompt, sessionData, fieldType, issueId, journalId, provider, requestType) {
    // Erstelle Anfrage
    const formData = new FormData();
    formData.append('original_text', originalText);
    formData.append('system_prompt', systemPrompt);
    formData.append('session_id', sessionData.sessionId);
    formData.append('field_type', fieldType);
    formData.append('issue_id', issueId || '');
    if (journalId) formData.append('journal_id', journalId);
    formData.append('provider', provider);
    formData.append('request_type', requestType);

    fetch('/ai_rewrite/rewrite', {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => {
      if (!response.ok) {
        return response.text().then(text => {
          throw new Error('HTTP ' + response.status + ': ' + text.substring(0, 200));
        });
      }
      return response.json();
    })
    .then(data => {
      setButtonLoading(button, false);

      console.log('AI Rewrite Response:', data);

      if (data.error) {
        alert('Fehler: ' + data.error);
        return;
      }

      console.log('AI Rewrite Success - Improved text length:', data.improved_text ? data.improved_text.length : 0);

      // Verbesserten Text einfügen
      if (data.improved_text && data.improved_text.trim().length > 0) {
        if (!document.contains(textarea)) {
          console.warn('AI Rewrite - Textarea reference is no longer in DOM, trying to find by ID');
          const newTextarea = document.getElementById(textarea.id);
          if (newTextarea) {
            textarea = newTextarea;
          }
        }
        
        textarea.value = data.improved_text;
        
        // Trigger event for Redmine
        if (window.jQuery) {
          window.jQuery(textarea).trigger('change').trigger('input');
        } else {
          const event = new Event('input', { bubbles: true });
          textarea.dispatchEvent(event);
        }
      } else {
        console.warn('AI Rewrite returned empty text');
        alert('Die KI hat eine leere Antwort geliefert. Bitte prüfen Sie Ihre Einstellungen oder versuchen Sie es erneut.');
      }
      
      sessionData.versionId = data.version_id;
      
      // Buttons aktualisieren
      prevButton.style.display = 'inline-block';
      nextButton.style.display = 'inline-block';
      
      // Navigation-Status aktualisieren
      sessionData.versionHistory.canGoPrev = true;
      sessionData.versionHistory.canGoNext = false;
      updateNavigationButtons(textarea, prevButton, nextButton);

      // Versionsauswahl aktualisieren
      const versionSelect = textarea.parentNode.querySelector('.ai-version-select');
      if (versionSelect) {
        populateVersionSelect(versionSelect, textarea);
        versionSelect.style.display = 'inline-block';
      }

      // Event für Textänderungen durch Benutzer
      textarea.addEventListener('input', function onInput() {
        if (sessionData.versionId) {
          saveCurrentVersion(textarea.value, sessionData.versionId);
        }
        textarea.removeEventListener('input', onInput);
      });
    })
    .catch(error => {
      setButtonLoading(button, false);
      console.error('Fehler bei der KI-Anfrage:', error);
      alert('Fehler bei der KI-Anfrage: ' + error.message);
    });
  }

  // Alte Rewrite-Funktion (umbenannt für Kompatibilität)
  function handleRewrite(textarea, rewriteButton, prevButton, nextButton, promptInput) {
    const originalText = textarea.value;
    const customPrompt = promptInput.value.trim();
    
    let systemPrompt = '';
    
    if (customPrompt) {
      systemPrompt = customPrompt;
    } else {
      systemPrompt = 'Verbessere den folgenden Text, korrigiere Rechtschreib- und Grammatikfehler, verbessere die Struktur und mache ihn professioneller, während der ursprüngliche Sinn und Inhalt erhalten bleibt. Antworte nur mit dem verbesserten Text, ohne zusätzliche Erklärungen.';
    }

    handleAIRequest(textarea, rewriteButton, prevButton, nextButton, originalText, systemPrompt, 'rewrite');
  }

  // Button-Loading Status setzen
  function setButtonLoading(button, loading) {
    const textSpan = button.querySelector('.btn-text');
    if (loading) {
      button.classList.add('disabled');
      button.style.pointerEvents = 'none';
      if (textSpan) {
        button.setAttribute('data-original-text', textSpan.textContent);
        textSpan.textContent = 'Lädt...';
      }
    } else {
      button.classList.remove('disabled');
      button.style.pointerEvents = 'auto';
      const originalText = button.getAttribute('data-original-text');
      if (originalText && textSpan) {
        textSpan.textContent = originalText;
        button.removeAttribute('data-original-text');
      }
    }
  }

  // Navigations-Buttons aktualisieren
  function updateNavigationButtons(textarea, prevButton, nextButton) {
    const sessionData = getSessionData(textarea);
    prevButton.disabled = !sessionData.versionHistory.canGoPrev;
    nextButton.disabled = !sessionData.versionHistory.canGoNext;
  }

  // Vorhandene Versionen prüfen
  function checkExistingVersions(textarea, prevButton, nextButton) {
    const issueId = extractIssueIdFromUrl();
    const journalId = extractJournalId(textarea);
    const fieldType = detectFieldType(textarea);
    const sessionData = getSessionData(textarea);
    
    const params = new URLSearchParams({
      issue_id: issueId,
      field_type: fieldType
    });
    if (journalId) params.append('journal_id', journalId);
    
    return fetch('/ai_rewrite/check_versions?' + params.toString(), {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data && data.has_versions) {
        sessionData.sessionId = data.session_id;
        sessionData.versionId = data.version_id;
        sessionData.versionHistory.canGoPrev = data.can_go_prev;
        sessionData.versionHistory.canGoNext = data.can_go_next;
        
        prevButton.style.display = 'inline-block';
        nextButton.style.display = 'inline-block';
        updateNavigationButtons(textarea, prevButton, nextButton);
        
        return true;
      }
      return false;
    })
    .catch(error => {
      console.error('Fehler beim Prüfen der Versionen:', error);
      return false;
    });
  }

  // Version navigieren
  function handleNavigateVersion(textarea, direction, prevButton, nextButton) {
    const sessionData = getSessionData(textarea);
    if (!sessionData.versionId) return;
    
    const url = '/ai_rewrite/get_version?version_id=' + encodeURIComponent(sessionData.versionId) + 
                '&direction=' + direction + '&session_id=' + encodeURIComponent(sessionData.sessionId || '');
    
    fetch(url, {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      textarea.value = data.text;
      sessionData.versionId = data.version_id;
      sessionData.versionHistory.canGoPrev = data.can_go_prev;
      sessionData.versionHistory.canGoNext = data.can_go_next;
      updateNavigationButtons(textarea, prevButton, nextButton);
      
      const versionSelect = textarea.parentNode.querySelector('.ai-version-select');
      if (versionSelect) {
        setSelectedVersionInSelect(versionSelect, sessionData.versionId);
      }
    })
    .catch(error => {
      console.error('Fehler beim Navigieren:', error);
      alert('Fehler beim Laden der Version: ' + error.message);
    });
  }

  // Exakte Version navigieren
  function handleNavigateExactVersion(textarea, versionId, prevButton, nextButton) {
    const sessionData = getSessionData(textarea);
    const url = '/ai_rewrite/get_version?version_id=' + encodeURIComponent(versionId) + 
                '&direction=exact&session_id=' + encodeURIComponent(sessionData.sessionId || '');
    
    fetch(url, {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      textarea.value = data.text;
      sessionData.versionId = data.version_id;
      sessionData.versionHistory.canGoPrev = data.can_go_prev;
      sessionData.versionHistory.canGoNext = data.can_go_next;
      updateNavigationButtons(textarea, prevButton, nextButton);
    })
    .catch(error => {
      console.error('Fehler beim Laden der Version:', error);
      alert('Fehler beim Laden der Version: ' + error.message);
    });
  }

  // Versionsliste laden
  function populateVersionSelect(versionSelect, textarea) {
    const issueId = extractIssueIdFromUrl();
    const journalId = extractJournalId(textarea);
    const fieldType = detectFieldType(textarea);
    const sessionData = getSessionData(textarea);
    
    const params = new URLSearchParams();
    if (sessionData.sessionId) params.append('session_id', sessionData.sessionId);
    if (issueId) params.append('issue_id', issueId);
    if (journalId) params.append('journal_id', journalId);
    params.append('field_type', fieldType);
    
    fetch('/ai_rewrite/list_versions?' + params.toString(), {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      const versions = data.versions || [];
      versionSelect.innerHTML = '';
      versions.forEach(function(v) {
        const opt = document.createElement('option');
        opt.value = v.version_id;
        opt.textContent = v.label;
        versionSelect.appendChild(opt);
      });
      if (versions.length > 0) {
        versionSelect.style.display = 'inline-block';
        setSelectedVersionInSelect(versionSelect, sessionData.versionId);
      } else {
        versionSelect.style.display = 'none';
      }
    })
    .catch(error => {
      console.error('Fehler beim Laden der Versionsliste:', error);
    });
  }

  function setSelectedVersionInSelect(versionSelect, versionId) {
    if (!versionId) return;
    const options = Array.from(versionSelect.options);
    const found = options.find(o => o.value === versionId);
    if (found) {
      versionSelect.value = versionId;
    }
  }

  function ensureOriginalVersionSaved(originalText, sessionId, fieldType, issueId, journalId) {
    if (!originalText) return;
    
    const formData = new FormData();
    formData.append('original_text', originalText);
    formData.append('session_id', sessionId);
    formData.append('field_type', fieldType);
    formData.append('issue_id', issueId || '');
    if (journalId) formData.append('journal_id', journalId);

    fetch('/ai_rewrite/save_version', {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .catch(error => {
      console.error('Fehler beim Speichern der Originalversion:', error);
    });
  }

  function saveCurrentVersion(text, versionId) {
    if (!versionId) return;
    
    const formData = new FormData();
    formData.append('text', text);
    formData.append('version_id', versionId);

    fetch('/ai_rewrite/save_version', {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .catch(error => {
      console.error('Fehler beim Speichern der Version:', error);
    });
  }

  function detectFieldType(textarea) {
    if (textarea.id && textarea.id.includes('notes')) {
      return 'notes';
    } else if (textarea.id && textarea.id.includes('description')) {
      return 'description';
    }
    // Fallback auf den Namen, falls ID nicht eindeutig
    if (textarea.name && textarea.name.includes('notes')) {
      return 'notes';
    }
    return 'description';
  }

  function extractJournalId(textarea) {
    // Versuche Journal-ID aus der ID der Textarea zu extrahieren (z.B. journal_123_notes)
    let match = textarea.id.match(/journal_(\d+)_notes/);
    if (match) return match[1];

    // Versuche aus dem umschließenden Formular zu extrahieren
    const form = textarea.closest('form');
    if (form && form.id) {
      match = form.id.match(/journal-(\d+)-form/);
      if (match) return match[1];
    }

    // Versuche aus einem Hidden-Feld im Formular
    if (form) {
      const journalIdField = form.querySelector('input[name="journal_id"]');
      if (journalIdField) return journalIdField.value;
    }

    return null;
  }

  function extractIssueIdFromUrl() {
    const match = window.location.pathname.match(/\/issues\/(\d+)/);
    return match ? match[1] : null;
  }

  function getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]');
    return token ? token.getAttribute('content') : '';
  }

  // Neue Funktion: Hole AI Settings aus dem Backend
  function loadAISettings() {
    return fetch('/ai_rewrite/settings', {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      window.redmineAISettings = data.settings || {};
      return data.settings;
    })
    .catch(error => {
      console.error('Fehler beim Laden der Settings:', error);
      return {};
    });
  }

  // Textareas automatisch mit AI-Buttons versehen
  function attachToTextareas() {
    const textareas = document.querySelectorAll('textarea');
    textareas.forEach(function(textarea) {
      // Prüfen ob es sich um eine relevante Textarea handelt
      if (textarea.id && (textarea.id.includes('notes') || textarea.id.includes('description'))) {
        createAIButtons(textarea);
      }
    });
  }

  // Initialisierung
  function init() {
    // Lade Settings
    loadAISettings().then(function(settings) {
      window.redmineAISettings = settings;
      
      // Beobachte DOM-Änderungen für neue Textareas
      const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          mutation.addedNodes.forEach(function(node) {
            if (node.nodeType === 1) { // Element-Knoten
              // Prüfe das hinzugefügte Element selbst
              if (node.tagName === 'TEXTAREA') {
                if (node.id && (node.id.includes('notes') || node.id.includes('description'))) {
                  createAIButtons(node);
                }
              }
              
              // Prüfe Kinder des hinzugefügten Elements
              const textareas = node.querySelectorAll ? node.querySelectorAll('textarea') : [];
              textareas.forEach(function(textarea) {
                if (textarea.id && (textarea.id.includes('notes') || textarea.id.includes('description'))) {
                  createAIButtons(textarea);
                }
              });
            }
          });
        });
      });

      observer.observe(document.body, {
        childList: true,
        subtree: true
      });

      // Vorhandene Textareas verarbeiten
      attachToTextareas();
    });
  }

  // Initialisierung beim DOM-Ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Fallback für später geladene Seiten
  window.addEventListener('load', function() {
    setTimeout(init, 100);
  });

})();
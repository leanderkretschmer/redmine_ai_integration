(function() {
  'use strict';

  let currentSessionId = null;
  let currentVersionId = null;
  let versionHistory = {
    canGoPrev: false,
    canGoNext: false
  };

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

    const buttonContainer = document.createElement('div');
    buttonContainer.className = 'ai-buttons-container';
    buttonContainer.style.cssText = 'position: relative; display: block; width: 100%; margin-top: 5px;';

    const buttonGroup = document.createElement('div');
    buttonGroup.className = 'ai-button-group';
    buttonGroup.style.cssText = 'display: flex; gap: 5px; align-items: center; margin-bottom: 5px; flex-wrap: wrap;';

    // Korrektur Button (neu)
    const correctionButton = document.createElement('button');
    correctionButton.type = 'button';
    correctionButton.className = 'ai-correction-button button';
    correctionButton.innerHTML = '<span>🔧</span> <span>Korrektur</span>';
    correctionButton.title = 'Automatische Korrektur ohne zusätzliche Eingabe';

    // Komplexe Anfrage Button (neu)
    const complexButton = document.createElement('button');
    complexButton.type = 'button';
    complexButton.className = 'ai-complex-button button';
    complexButton.innerHTML = '<span>✨</span> <span>Erweitern</span>';
    complexButton.title = 'Komplexe Anfrage mit benutzerdefinierter Anweisung';

    // Navigation Buttons (wie vorher)
    const prevButton = document.createElement('button');
    prevButton.type = 'button';
    prevButton.className = 'ai-prev-button button';
    prevButton.innerHTML = '&lt;';
    prevButton.style.cssText = 'display: none;';
    prevButton.title = 'Vorherige Version';

    const nextButton = document.createElement('button');
    nextButton.type = 'button';
    nextButton.className = 'ai-next-button button';
    nextButton.innerHTML = '&gt;';
    nextButton.style.cssText = 'display: none;';
    nextButton.title = 'Nächste Version';

    // Versionsauswahl (Dropdown)
    const versionSelect = document.createElement('select');
    versionSelect.className = 'ai-version-select';
    versionSelect.style.cssText = 'display:none; min-width: 120px;';
    versionSelect.title = 'Version auswählen';

    // Komplexe Anfrage Input (neu)
    const complexInput = document.createElement('input');
    complexInput.type = 'text';
    complexInput.className = 'ai-complex-input';
    complexInput.placeholder = 'z.B. "Fülle die Tabelle aus" oder "Erweitere die Beschreibung"...';
    complexInput.style.cssText = 'display: none; width: 100%; margin-top: 5px; padding: 4px 8px; font-size: 12px; border: 1px solid #ccc; border-radius: 3px;';

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
    
    let systemPrompt = 'Korrigiere Rechtschreibung, Grammatik und Satzstellung. Verbessere die Struktur und mache den Text professioneller.';
    
    if (isSlimResponse) {
      systemPrompt += ' Antworte nur mit dem korrigierten Text, ohne Erklärungen.';
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

    const systemPrompt = `Führe folgende Anweisung aus: "${userInstruction}". Text: "${originalText}"`;
    
    handleAIRequest(textarea, complexButton, prevButton, nextButton, originalText, systemPrompt, 'complex');
    
    // Verstecke Input wieder
    complexInput.style.display = 'none';
    complexInput.value = '';
  }

  // Generische AI-Anfrage Funktion
  function handleAIRequest(textarea, button, prevButton, nextButton, originalText, systemPrompt, requestType) {
    const issueId = extractIssueIdFromUrl();
    const fieldType = detectFieldType(textarea);
    
    if (!currentSessionId) {
      currentSessionId = generateSessionId();
    }

    // Speichere Original-Version wenn noch nicht vorhanden
    if (!currentVersionId) {
      ensureOriginalVersionSaved(originalText, currentSessionId, fieldType, issueId);
    }

    // Button-Status setzen
    setButtonLoading(button, true);
    button.disabled = true;

    // Hole Settings
    const settings = window.redmineAISettings || {};
    const provider = settings.ai_provider || 'openai';

    // Erstelle Anfrage
    const formData = new FormData();
    formData.append('original_text', originalText);
    formData.append('system_prompt', systemPrompt);
    formData.append('session_id', currentSessionId);
    formData.append('field_type', fieldType);
    formData.append('issue_id', issueId || '');
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
      button.disabled = false;

      if (data.error) {
        alert('Fehler: ' + data.error);
        return;
      }

      // Verbesserten Text einfügen
      textarea.value = data.improved_text;
      currentVersionId = data.version_id;
      
      // Buttons aktualisieren
      prevButton.style.display = 'inline-block';
      nextButton.style.display = 'inline-block';
      
      // Navigation-Status aktualisieren
      versionHistory.canGoPrev = true;
      versionHistory.canGoNext = false;
      updateNavigationButtons(prevButton, nextButton);

      // Versionsauswahl aktualisieren
      const versionSelect = textarea.parentNode.querySelector('.ai-version-select');
      if (versionSelect) {
        populateVersionSelect(versionSelect, textarea);
        versionSelect.style.display = 'inline-block';
      }

      // Event für Textänderungen durch Benutzer
      textarea.addEventListener('input', function onInput() {
        if (currentVersionId) {
          saveCurrentVersion(textarea.value, currentVersionId);
        }
        textarea.removeEventListener('input', onInput);
      });
    })
    .catch(error => {
      setButtonLoading(button, false);
      button.disabled = false;
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

  // Rest der Funktionen bleibt gleich...
  function setButtonLoading(button, loading) {
    if (loading) {
      button.disabled = true;
      const originalText = button.querySelector('.ai-rewrite-text') || button.querySelector('span:last-child');
      if (originalText) {
        button.setAttribute('data-original-text', originalText.textContent);
        originalText.textContent = 'Lädt...';
      }
    } else {
      button.disabled = false;
      const originalText = button.getAttribute('data-original-text');
      if (originalText) {
        const textElement = button.querySelector('.ai-rewrite-text') || button.querySelector('span:last-child');
        if (textElement) {
          textElement.textContent = originalText;
        }
        button.removeAttribute('data-original-text');
      }
    }
  }

  function updateNavigationButtons(prevButton, nextButton) {
    prevButton.disabled = !versionHistory.canGoPrev;
    nextButton.disabled = !versionHistory.canGoNext;
  }

  function checkExistingVersions(textarea, prevButton, nextButton) {
    const issueId = extractIssueIdFromUrl();
    const fieldType = detectFieldType(textarea);
    
    return fetch('/ai_rewrite/check_versions?' + new URLSearchParams({
      issue_id: issueId,
      field_type: fieldType
    }), {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data && data.has_versions) {
        currentSessionId = data.session_id;
        currentVersionId = data.version_id;
        versionHistory.canGoPrev = data.can_go_prev;
        versionHistory.canGoNext = data.can_go_next;
        
        prevButton.style.display = 'inline-block';
        nextButton.style.display = 'inline-block';
        updateNavigationButtons(prevButton, nextButton);
        
        return true;
      }
      return false;
    })
    .catch(error => {
      console.error('Fehler beim Prüfen der Versionen:', error);
      return false;
    });
  }

  function handleNavigateVersion(textarea, direction, prevButton, nextButton) {
    if (!currentVersionId) return;
    
    const url = '/ai_rewrite/get_version?version_id=' + encodeURIComponent(currentVersionId) + 
                '&direction=' + direction + '&session_id=' + encodeURIComponent(currentSessionId || '');
    
    fetch(url, {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      textarea.value = data.text;
      currentVersionId = data.version_id;
      versionHistory.canGoPrev = data.can_go_prev;
      versionHistory.canGoNext = data.can_go_next;
      updateNavigationButtons(prevButton, nextButton);
      
      const versionSelect = textarea.parentNode.querySelector('.ai-version-select');
      if (versionSelect) {
        setSelectedVersionInSelect(versionSelect, currentVersionId);
      }
    })
    .catch(error => {
      console.error('Fehler beim Navigieren:', error);
      alert('Fehler beim Laden der Version: ' + error.message);
    });
  }

  function handleNavigateExactVersion(textarea, versionId, prevButton, nextButton) {
    const url = '/ai_rewrite/get_version?version_id=' + encodeURIComponent(versionId) + 
                '&direction=exact&session_id=' + encodeURIComponent(currentSessionId || '');
    
    fetch(url, {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      textarea.value = data.text;
      currentVersionId = data.version_id;
      versionHistory.canGoPrev = data.can_go_prev;
      versionHistory.canGoNext = data.can_go_next;
      updateNavigationButtons(prevButton, nextButton);
    })
    .catch(error => {
      console.error('Fehler beim Laden der Version:', error);
      alert('Fehler beim Laden der Version: ' + error.message);
    });
  }

  function populateVersionSelect(versionSelect, textarea) {
    const issueId = extractIssueIdFromUrl();
    let fieldType = 'description';
    if (textarea.id && textarea.id.includes('notes')) {
      fieldType = 'notes';
    } else if (textarea.id && textarea.id.includes('description')) {
      fieldType = 'description';
    }
    
    const params = new URLSearchParams();
    if (currentSessionId) params.append('session_id', currentSessionId);
    if (issueId) params.append('issue_id', issueId);
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
        setSelectedVersionInSelect(versionSelect, currentVersionId);
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

  function ensureOriginalVersionSaved(originalText, sessionId, fieldType, issueId) {
    if (!originalText) return;
    
    const formData = new FormData();
    formData.append('original_text', originalText);
    formData.append('session_id', sessionId);
    formData.append('field_type', fieldType);
    formData.append('issue_id', issueId || '');

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
    return 'description';
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
    // Settings werden normalerweise vom Server gerendert
    // Als Fallback können wir sie auch per AJAX holen
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
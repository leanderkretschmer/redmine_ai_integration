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

  // Rewrite-Button erstellen
  function createRewriteButton(textarea) {
    // Prüfen ob Button bereits existiert
    if (textarea.parentNode.querySelector('.ai-rewrite-button')) {
      return;
    }

    const buttonContainer = document.createElement('div');
    buttonContainer.className = 'ai-rewrite-container';
    buttonContainer.style.cssText = 'position: relative; display: inline-block; width: 100%; margin-top: 5px;';

    const buttonGroup = document.createElement('div');
    buttonGroup.className = 'ai-rewrite-button-group';
    buttonGroup.style.cssText = 'display: flex; gap: 5px; align-items: center;';

    // Rewrite Button
    const rewriteButton = document.createElement('button');
    rewriteButton.type = 'button';
    rewriteButton.className = 'ai-rewrite-button button';
    rewriteButton.innerHTML = '<span class="ai-rewrite-icon"></span> <span class="ai-rewrite-text">Rewrite</span>';
    
    // Undo Button (initial versteckt)
    const undoButton = document.createElement('button');
    undoButton.type = 'button';
    undoButton.className = 'ai-undo-button button';
    undoButton.innerHTML = '<span class="ai-undo-icon"></span> <span class="ai-undo-text">Rückgängig</span>';
    undoButton.style.cssText = 'display: none;';

    // Navigation Buttons (initial versteckt)
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

    // Custom Prompt Input
    const promptInput = document.createElement('input');
    promptInput.type = 'text';
    promptInput.className = 'ai-custom-prompt-input';
    promptInput.placeholder = 'Optional: Eigener Prompt...';
    promptInput.title = 'Optional: Überschreibt den Standard-System-Prompt';

    buttonGroup.appendChild(rewriteButton);
    buttonGroup.appendChild(undoButton);
    buttonGroup.appendChild(prevButton);
    buttonGroup.appendChild(nextButton);
    buttonGroup.appendChild(promptInput);
    buttonContainer.appendChild(buttonGroup);

    // Button nach Textarea einfügen
    textarea.parentNode.insertBefore(buttonContainer, textarea.nextSibling);

    // Event Listeners
    rewriteButton.addEventListener('click', function() {
      handleRewrite(textarea, rewriteButton, undoButton, prevButton, nextButton, promptInput);
    });

    undoButton.addEventListener('click', function() {
      handleUndo(textarea, rewriteButton, undoButton, prevButton, nextButton);
    });

    prevButton.addEventListener('click', function() {
      handleNavigateVersion(textarea, 'prev', prevButton, nextButton);
    });

    nextButton.addEventListener('click', function() {
      handleNavigateVersion(textarea, 'next', prevButton, nextButton);
    });

    // Session-ID initialisieren wenn Textarea fokussiert wird
    textarea.addEventListener('focus', function() {
      if (!currentSessionId) {
        checkExistingVersions(textarea, undoButton, prevButton, nextButton).then(function(hasVersions) {
          // Nur neue Session-ID generieren, wenn keine Versionen gefunden wurden
          if (!hasVersions && !currentSessionId) {
            currentSessionId = generateSessionId();
          }
        });
      }
    });
    
    // Beim Laden prüfen, ob bereits Versionen existieren
    checkExistingVersions(textarea, undoButton, prevButton, nextButton);
  }
  
  // Prüfe ob bereits Versionen für dieses Issue/Field existieren
  function checkExistingVersions(textarea, undoButton, prevButton, nextButton) {
    if (currentSessionId) {
      return Promise.resolve(false); // Bereits eine Session vorhanden
    }
    
    const issueId = extractIssueIdFromUrl();
    if (!issueId) {
      return Promise.resolve(false); // Keine Issue-ID gefunden
    }
    
    // Field-Type bestimmen
    let fieldType = 'description';
    if (textarea.id && textarea.id.includes('notes')) {
      fieldType = 'notes';
    } else if (textarea.id && textarea.id.includes('description')) {
      fieldType = 'description';
    }
    
    const url = '/ai_rewrite/check_versions?issue_id=' + encodeURIComponent(issueId) + '&field_type=' + encodeURIComponent(fieldType);
    
    return fetch(url, {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => {
      if (!response.ok) {
        return null;
      }
      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        return response.json();
      }
      return null;
    })
    .then(data => {
      if (data && data.has_versions) {
        // Session-ID wiederherstellen
        currentSessionId = data.session_id;
        currentVersionId = data.version_id;
        versionHistory.canGoPrev = data.can_go_prev;
        versionHistory.canGoNext = data.can_go_next;
        
        // Buttons anzeigen
        undoButton.style.display = 'inline-block';
        prevButton.style.display = 'inline-block';
        nextButton.style.display = 'inline-block';
        updateNavigationButtons(prevButton, nextButton);
        
        console.log('Versions wiederhergestellt. Session ID:', currentSessionId, 'Version ID:', currentVersionId);
        return true;
      }
      return false;
    })
    .catch(error => {
      console.error('Fehler beim Prüfen der Versionen:', error);
      return false;
    });
  }
  
  // Issue-ID aus URL extrahieren
  function extractIssueIdFromUrl() {
    const match = window.location.pathname.match(/\/issues\/(\d+)/);
    return match ? match[1] : null;
  }

  // Rewrite durchführen
  function handleRewrite(textarea, rewriteButton, undoButton, prevButton, nextButton, promptInput) {
    const originalText = textarea.value;
    
    if (!originalText.trim()) {
      alert('Bitte geben Sie zuerst Text ein.');
      return;
    }

    // Lade-Animation starten
    setButtonLoading(rewriteButton, true);
    rewriteButton.disabled = true;

    // Originaltext speichern (falls noch keine Session existiert)
    if (!currentSessionId) {
      currentSessionId = generateSessionId();
    }

    // Immer normale API verwenden (kein Streaming)
    handleRewriteNormal(textarea, rewriteButton, undoButton, prevButton, nextButton, originalText, promptInput);
  }

  // Normale Rewrite-Funktion (ohne Streaming)
  function handleRewriteNormal(textarea, rewriteButton, undoButton, prevButton, nextButton, originalText, promptInput) {
    const url = '/ai_rewrite/rewrite';
    
    const formData = new FormData();
    formData.append('text', originalText);
    formData.append('session_id', currentSessionId);
    
    // Custom Prompt hinzufügen, falls vorhanden
    const customPrompt = promptInput ? promptInput.value.trim() : '';
    if (customPrompt) {
      formData.append('custom_prompt', customPrompt);
    }

    fetch(url, {
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
      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        return response.json();
      } else {
        return response.text().then(text => {
          throw new Error('Ungültige Antwort: Erwartet JSON, erhalten: ' + text.substring(0, 200));
        });
      }
    })
    .then(data => {
      setButtonLoading(rewriteButton, false);
      rewriteButton.disabled = false;

      if (data.error) {
        alert('Fehler: ' + data.error);
        return;
      }

      // Verbesserten Text einfügen
      textarea.value = data.improved_text;
      currentVersionId = data.version_id;
      
      // Debug-Logging
      console.log('Rewrite abgeschlossen. Version ID:', currentVersionId, 'Session ID:', currentSessionId);

      // Buttons aktualisieren
      undoButton.style.display = 'inline-block';
      prevButton.style.display = 'inline-block';
      nextButton.style.display = 'inline-block';
      
      // Navigation-Status aktualisieren
      versionHistory.canGoPrev = true;
      versionHistory.canGoNext = false;
      updateNavigationButtons(prevButton, nextButton);

      // Event für Textänderungen durch Benutzer
      textarea.addEventListener('input', function onInput() {
        if (currentVersionId) {
          saveCurrentVersion(textarea.value, currentVersionId);
        }
        textarea.removeEventListener('input', onInput);
      });
    })
    .catch(error => {
      setButtonLoading(rewriteButton, false);
      rewriteButton.disabled = false;
      console.error('Fehler:', error);
      alert('Fehler beim Verbessern des Textes: ' + error.message);
    });
  }

  // Rückgängig machen
  function handleUndo(textarea, rewriteButton, undoButton, prevButton, nextButton) {
    console.log('Undo aufgerufen. Version ID:', currentVersionId, 'Session ID:', currentSessionId);
    
    if (!currentVersionId || !currentSessionId) {
      console.error('Fehlende IDs:', { currentVersionId, currentSessionId });
      alert('Keine Version zum Rückgängig machen verfügbar.');
      return;
    }

    // Originaltext wiederherstellen - hole die erste Version (Original)
    const url = '/ai_rewrite/get_version?version_id=' + encodeURIComponent(currentVersionId) + '&direction=original&session_id=' + encodeURIComponent(currentSessionId);

    fetch(url, {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => {
      if (!response.ok) {
        return response.text().then(text => {
          console.error('HTTP Fehler:', response.status, text);
          throw new Error('HTTP ' + response.status + ': ' + text.substring(0, 200));
        });
      }
      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        return response.json();
      } else {
        return response.text().then(text => {
          throw new Error('Ungültige Antwort: Erwartet JSON, erhalten: ' + text.substring(0, 200));
        });
      }
    })
    .then(data => {
      console.log('Undo Response:', data);
      
      if (data.error) {
        alert('Fehler: ' + data.error);
        console.error('Undo Error:', data);
        return;
      }

      textarea.value = data.text;
      currentVersionId = data.version_id;
      versionHistory.canGoPrev = data.can_go_prev;
      versionHistory.canGoNext = data.can_go_next;
      updateNavigationButtons(prevButton, nextButton);
      
      // Undo-Button verstecken wenn wir beim Original sind
      if (!data.can_go_next) {
        undoButton.style.display = 'none';
      } else {
        undoButton.style.display = 'inline-block';
      }
    })
    .catch(error => {
      console.error('Fehler beim Rückgängig machen:', error);
      alert('Fehler beim Rückgängig machen: ' + error.message);
    });
  }

  // Version navigieren
  function handleNavigateVersion(textarea, direction, prevButton, nextButton) {
    console.log('Navigate Version aufgerufen. Direction:', direction, 'Version ID:', currentVersionId, 'Session ID:', currentSessionId);
    
    if (!currentVersionId || !currentSessionId) {
      console.error('Fehlende IDs für Navigation:', { currentVersionId, currentSessionId });
      return;
    }

    const url = '/ai_rewrite/get_version?version_id=' + encodeURIComponent(currentVersionId) + '&direction=' + direction + '&session_id=' + encodeURIComponent(currentSessionId);

    fetch(url, {
      method: 'GET',
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    })
    .then(response => {
      if (!response.ok) {
        return response.text().then(text => {
          console.error('HTTP Fehler bei Navigation:', response.status, text);
          throw new Error('HTTP ' + response.status + ': ' + text.substring(0, 200));
        });
      }
      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        return response.json();
      } else {
        return response.text().then(text => {
          throw new Error('Ungültige Antwort: Erwartet JSON, erhalten: ' + text.substring(0, 200));
        });
      }
    })
    .then(data => {
      console.log('Navigate Version Response:', data);
      
      if (data.error) {
        console.error('Navigation Error:', data);
        alert('Fehler: ' + data.error);
        return;
      }

      textarea.value = data.text;
      currentVersionId = data.version_id;
      versionHistory.canGoPrev = data.can_go_prev;
      versionHistory.canGoNext = data.can_go_next;
      updateNavigationButtons(prevButton, nextButton);
    })
    .catch(error => {
      console.error('Fehler bei Navigation:', error);
      alert('Fehler bei Navigation: ' + error.message);
    });
  }

  // Aktuelle Version speichern
  function saveCurrentVersion(text, versionId) {
    if (!versionId || !currentSessionId) {
      return;
    }

    const url = '/ai_rewrite/save_version';
    
    const formData = new FormData();
    formData.append('text', text);
    formData.append('version_id', versionId);

    fetch(url, {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': getCSRFToken()
      }
    }).catch(error => {
      console.error('Fehler beim Speichern der Version:', error);
    });
  }

  // Navigation-Buttons aktualisieren
  function updateNavigationButtons(prevButton, nextButton) {
    prevButton.disabled = !versionHistory.canGoPrev;
    nextButton.disabled = !versionHistory.canGoNext;
    prevButton.style.opacity = versionHistory.canGoPrev ? '1' : '0.5';
    nextButton.style.opacity = versionHistory.canGoNext ? '1' : '0.5';
  }

  // Lade-Animation setzen
  function setButtonLoading(button, loading) {
    const icon = button.querySelector('.ai-rewrite-icon');
    const text = button.querySelector('.ai-rewrite-text');
    
    if (loading) {
      icon.innerHTML = '...';
      icon.classList.add('ai-spinning');
      text.textContent = 'Verarbeite...';
    } else {
      icon.innerHTML = '';
      icon.classList.remove('ai-spinning');
      text.textContent = 'Rewrite';
    }
  }

  // Projekt-ID aus URL extrahieren
  function getProjectId() {
    const match = window.location.pathname.match(/\/projects\/([^\/]+)/);
    return match ? match[1] : '';
  }

  // CSRF-Token holen
  function getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]');
    return token ? token.getAttribute('content') : '';
  }

  // Initialisierung wenn DOM bereit ist
  function init() {
    // Warten bis Redmine geladen ist
    if (typeof jQuery !== 'undefined') {
      jQuery(document).ready(function() {
        attachToTextareas();
      });
    } else {
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', attachToTextareas);
      } else {
        attachToTextareas();
      }
    }
  }

  // Buttons zu Textareas hinzufügen
  function attachToTextareas() {
    // Kommentar-Textarea
    const commentTextarea = document.getElementById('issue_notes');
    if (commentTextarea) {
      createRewriteButton(commentTextarea);
    }

    // Beschreibungs-Textarea
    const descriptionTextarea = document.getElementById('issue_description');
    if (descriptionTextarea) {
      createRewriteButton(descriptionTextarea);
    }

    // Weitere Textareas finden (für verschiedene Redmine-Versionen)
    const textareas = document.querySelectorAll('textarea.wiki-edit, textarea#content_text, textarea[name*="description"], textarea[name*="notes"]');
    textareas.forEach(function(textarea) {
      if (!textarea.parentNode.querySelector('.ai-rewrite-button')) {
        createRewriteButton(textarea);
      }
    });

    // Observer für dynamisch hinzugefügte Textareas
    const observer = new MutationObserver(function(mutations) {
      mutations.forEach(function(mutation) {
        mutation.addedNodes.forEach(function(node) {
          if (node.nodeType === 1) {
            const textareas = node.querySelectorAll ? node.querySelectorAll('textarea') : [];
            textareas.forEach(function(textarea) {
              if (textarea.id && (textarea.id.includes('description') || textarea.id.includes('notes') || textarea.id.includes('content'))) {
                createRewriteButton(textarea);
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
  }

  // Session beim Speichern zurücksetzen (aber Versionen bleiben in DB)
  function resetSession() {
    // Session-Variablen zurücksetzen, aber Versionen bleiben in der DB
    // Beim nächsten Laden werden sie wiederhergestellt
    currentSessionId = null;
    currentVersionId = null;
    versionHistory = { canGoPrev: false, canGoNext: false };
  }

  // Beim Speichern Session zurücksetzen
  if (typeof jQuery !== 'undefined') {
    jQuery(document).on('submit', 'form', function() {
      setTimeout(resetSession, 1000);
    });
  } else {
    document.addEventListener('submit', function(e) {
      setTimeout(resetSession, 1000);
    }, true);
  }

  // Initialisierung starten
  init();
})();


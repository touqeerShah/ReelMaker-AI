/**
 * ReelMaker-AI - Application Logic
 * Handles workflow selection, file upload, processing, and UI state management
 */

// ============================================
// Global State Management
// ============================================
const appState = {
    selectedWorkflow: null,
    uploadedFile: null,
    processingOptions: {},
    currentStep: 0,
    isProcessing: false
};

// Available languages for translation
const LANGUAGES = [
    { code: 'es', name: 'Spanish' },
    { code: 'fr', name: 'French' },
    { code: 'de', name: 'German' },
    { code: 'it', name: 'Italian' },
    { code: 'pt', name: 'Portuguese' },
    { code: 'ar', name: 'Arabic' },
    { code: 'hi', name: 'Hindi' },
    { code: 'zh', name: 'Mandarin' },
    { code: 'ja', name: 'Japanese' },
    { code: 'ko', name: 'Korean' }
];

// Processing steps for each workflow
const WORKFLOW_STEPS = {
    simple: [
        { id: 'upload', label: 'Upload', icon: '📤' },
        { id: 'process', label: 'Process', icon: '⚙️' },
        { id: 'subtitle', label: 'Subtitle', icon: '📝' },
        { id: 'translate', label: 'Translate', icon: '🌍' },
        { id: 'complete', label: 'Complete', icon: '✅' }
    ],
    ai: [
        { id: 'upload', label: 'Upload', icon: '📤' },
        { id: 'extract', label: 'Extract', icon: '🎵' },
        { id: 'transcribe', label: 'Transcribe', icon: '📄' },
        { id: 'summarize', label: 'Summarize', icon: '🤖' },
        { id: 'generate', label: 'Generate', icon: '🎬' },
        { id: 'complete', label: 'Complete', icon: '✅' }
    ]
};

// ============================================
// Initialization
// ============================================
document.addEventListener('DOMContentLoaded', function() {
    initializeLanguageTags();
    setupDragAndDrop();
    setupEventListeners();
});

/**
 * Initialize language selection tags
 */
function initializeLanguageTags() {
    const container = document.getElementById('languageTags');
    if (!container) return;
    
    LANGUAGES.forEach(lang => {
        const tag = document.createElement('div');
        tag.className = 'language-tag';
        tag.textContent = lang.name;
        tag.dataset.code = lang.code;
        tag.onclick = () => toggleLanguageTag(tag);
        container.appendChild(tag);
    });
}

/**
 * Toggle language tag selection
 */
function toggleLanguageTag(tag) {
    tag.classList.toggle('selected');
}

/**
 * Get selected languages
 */
function getSelectedLanguages() {
    const tags = document.querySelectorAll('.language-tag.selected');
    return Array.from(tags).map(tag => tag.dataset.code);
}

// ============================================
// Workflow Selection
// ============================================
function selectWorkflow(workflow) {
    appState.selectedWorkflow = workflow;
    
    // Update UI to show selected state
    document.querySelectorAll('.workflow-card').forEach(card => {
        card.classList.remove('selected');
    });
    
    const selectedCard = document.getElementById(`workflow-${workflow}`);
    if (selectedCard) {
        selectedCard.classList.add('selected');
    }
    
    // Show upload section with animation
    setTimeout(() => {
        showSection('upload-section');
        scrollToElement('upload-section');
    }, 300);
}

/**
 * Scroll to workflow section
 */
function scrollToWorkflow() {
    scrollToElement('workflow');
}

/**
 * Smooth scroll to element
 */
function scrollToElement(id) {
    const element = document.getElementById(id);
    if (element) {
        element.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
}

// ============================================
// File Upload & Drag-and-Drop
// ============================================
function setupDragAndDrop() {
    const uploadZone = document.getElementById('uploadZone');
    if (!uploadZone) return;
    
    uploadZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadZone.classList.add('drag-over');
    });
    
    uploadZone.addEventListener('dragleave', () => {
        uploadZone.classList.remove('drag-over');
    });
    
    uploadZone.addEventListener('drop', (e) => {
        e.preventDefault();
        uploadZone.classList.remove('drag-over');
        
        const files = e.dataTransfer.files;
        if (files.length > 0) {
            handleFile(files[0]);
        }
    });
}

/**
 * Handle file selection from input
 */
function handleFileSelect(event) {
    const file = event.target.files[0];
    if (file) {
        handleFile(file);
    }
}

/**
 * Process uploaded file
 */
function handleFile(file) {
    // Validate file type
    const validTypes = ['video/mp4', 'video/quicktime', 'video/x-msvideo', 'video/x-matroska'];
    if (!validTypes.includes(file.type)) {
        alert('Please upload a valid video file (MP4, MOV, AVI, MKV)');
        return;
    }
    
    // Validate file size (500MB max)
    const maxSize = 500 * 1024 * 1024;
    if (file.size > maxSize) {
        alert('File size exceeds 500MB limit');
        return;
    }
    
    appState.uploadedFile = file;
    
    // Display file info
    displayFileInfo(file);
    
    // Create video preview
    createVideoPreview(file);
    
    // Show options section
    setTimeout(() => {
        showSection('options-section');
        showWorkflowOptions();
        scrollToElement('options-section');
    }, 500);
}

/**
 * Display file information
 */
function displayFileInfo(file) {
    document.getElementById('fileName').textContent = file.name;
    document.getElementById('fileSize').textContent = formatFileSize(file.size);
    
    // Create temporary video to get duration
    const video = document.createElement('video');
    video.preload = 'metadata';
    video.onloadedmetadata = function() {
        const duration = formatDuration(video.duration);
        document.getElementById('fileDuration').textContent = duration;
        URL.revokeObjectURL(video.src);
    };
    video.src = URL.createObjectURL(file);
    
    showSection('fileInfo');
}

/**
 * Create video preview
 */
function createVideoPreview(file) {
    const preview = document.getElementById('previewVideo');
    if (preview) {
        preview.src = URL.createObjectURL(file);
        showSection('videoPreview');
    }
}

/**
 * Show workflow-specific options
 */
function showWorkflowOptions() {
    if (appState.selectedWorkflow === 'simple') {
        showSection('simple-options');
        hideSection('ai-options');
    } else if (appState.selectedWorkflow === 'ai') {
        showSection('ai-options');
        hideSection('simple-options');
    }
}

// ============================================
// Processing
// ============================================
function startProcessing() {
    if (!appState.uploadedFile) {
        alert('Please upload a video file first');
        return;
    }
    
    // Collect processing options
    collectProcessingOptions();
    
    // Hide options, show processing section
    hideSection('options-section');
    showSection('processing-section');
    scrollToElement('processing-section');
    
    // Initialize processing steps
    initializeProcessingSteps();
    
    // Start processing simulation
    appState.isProcessing = true;
    simulateProcessing();
}

/**
 * Collect processing options from form
 */
function collectProcessingOptions() {
    if (appState.selectedWorkflow === 'simple') {
        appState.processingOptions = {
            split: document.getElementById('option-split').checked,
            subtitles: document.getElementById('option-subtitles').checked,
            languages: getSelectedLanguages(),
            subtitleStyle: document.getElementById('subtitle-style').value
        };
    } else if (appState.selectedWorkflow === 'ai') {
        const summaryLength = document.getElementById('summary-length').value;
        const lengthMap = { '1': 'short', '2': 'medium', '3': 'comprehensive' };
        
        appState.processingOptions = {
            summaryLength: lengthMap[summaryLength],
            voice: document.getElementById('ai-voice').value,
            outputLanguage: document.getElementById('output-language').value,
            chapters: document.getElementById('option-chapters').checked
        };
    }
}

/**
 * Initialize processing steps UI
 */
function initializeProcessingSteps() {
    const container = document.getElementById('processingSteps');
    if (!container) return;
    
    container.innerHTML = '';
    const steps = WORKFLOW_STEPS[appState.selectedWorkflow] || [];
    
    steps.forEach((step, index) => {
        const stepDiv = document.createElement('div');
        stepDiv.className = 'step';
        stepDiv.id = `step-${index}`;
        
        stepDiv.innerHTML = `
            <div class="step-icon">${step.icon}</div>
            <div class="step-label">${step.label}</div>
        `;
        
        container.appendChild(stepDiv);
    });
}

/**
 * Simulate processing (for demo purposes)
 */
function simulateProcessing() {
    const steps = WORKFLOW_STEPS[appState.selectedWorkflow] || [];
    const totalSteps = steps.length;
    let currentStep = 0;
    
    const progressMessages = appState.selectedWorkflow === 'simple' 
        ? [
            'Uploading video...',
            'Processing video file...',
            'Generating subtitles from audio...',
            'Translating to selected languages...',
            'Finalizing video...'
        ]
        : [
            'Uploading video...',
            'Extracting audio from video...',
            'Transcribing speech to text...',
            'Analyzing and summarizing content...',
            'Generating video clips and narration...',
            'Combining clips into summary video...'
        ];
    
    const interval = setInterval(() => {
        if (currentStep < totalSteps) {
            // Update step status
            updateStepStatus(currentStep, 'active');
            
            // Update progress bar
            const progress = ((currentStep + 1) / totalSteps) * 100;
            updateProgress(progress, progressMessages[currentStep]);
            
            // Add log entry
            addProcessingLog(progressMessages[currentStep]);
            
            // Mark previous step as completed
            if (currentStep > 0) {
                updateStepStatus(currentStep - 1, 'completed');
            }
            
            currentStep++;
        } else {
            clearInterval(interval);
            updateStepStatus(totalSteps - 1, 'completed');
            completeProcessing();
        }
    }, 2000); // 2 seconds per step
}

/**
 * Update step status
 */
function updateStepStatus(stepIndex, status) {
    const step = document.getElementById(`step-${stepIndex}`);
    if (!step) return;
    
    step.classList.remove('active', 'completed');
    if (status) {
        step.classList.add(status);
    }
}

/**
 * Update progress bar
 */
function updateProgress(percentage, message) {
    const progressFill = document.getElementById('progressFill');
    const progressText = document.getElementById('progressText');
    
    if (progressFill) {
        progressFill.style.width = `${percentage}%`;
    }
    
    if (progressText) {
        progressText.textContent = `${Math.round(percentage)}% - ${message}`;
    }
}

/**
 * Add processing log entry
 */
function addProcessingLog(message) {
    const logsContainer = document.getElementById('processingLogs');
    if (!logsContainer) return;
    
    const timestamp = new Date().toLocaleTimeString();
    const logEntry = document.createElement('div');
    logEntry.style.marginBottom = '0.5rem';
    logEntry.innerHTML = `<span style="color: var(--color-text-muted);">[${timestamp}]</span> ${message}`;
    
    logsContainer.appendChild(logEntry);
    logsContainer.scrollTop = logsContainer.scrollHeight;
}

/**
 * Complete processing and show results
 */
function completeProcessing() {
    appState.isProcessing = false;
    updateProgress(100, 'Processing complete!');
    
    setTimeout(() => {
        hideSection('processing-section');
        showResults();
        scrollToElement('results-section');
    }, 1500);
}

/**
 * Show results section
 */
function showResults() {
    showSection('results-section');
    
    // Display processing summary
    displayProcessingSummary();
    
    // For demo, reuse the uploaded video as result
    const resultVideo = document.getElementById('resultVideo');
    if (resultVideo && appState.uploadedFile) {
        resultVideo.src = URL.createObjectURL(appState.uploadedFile);
    }
}

/**
 * Display processing summary
 */
function displayProcessingSummary() {
    const container = document.getElementById('processingSummary');
    if (!container) return;
    
    const options = appState.processingOptions;
    let summaryHTML = '<ul style="list-style: none; padding: 0;">';
    
    if (appState.selectedWorkflow === 'simple') {
        summaryHTML += `
            <li><strong>Workflow:</strong> Simple Processing</li>
            <li><strong>Video Split:</strong> ${options.split ? 'Yes' : 'No'}</li>
            <li><strong>Subtitles:</strong> ${options.subtitles ? 'Generated' : 'Not generated'}</li>
            <li><strong>Translations:</strong> ${options.languages.length > 0 ? options.languages.join(', ') : 'None'}</li>
            <li><strong>Subtitle Style:</strong> ${options.subtitleStyle}</li>
        `;
    } else {
        summaryHTML += `
            <li><strong>Workflow:</strong> AI Summary Pipeline</li>
            <li><strong>Summary Length:</strong> ${options.summaryLength}</li>
            <li><strong>AI Voice:</strong> ${options.voice}</li>
            <li><strong>Output Language:</strong> ${options.outputLanguage}</li>
            <li><strong>Chapters:</strong> ${options.chapters ? 'Yes' : 'No'}</li>
        `;
    }
    
    summaryHTML += '</ul>';
    container.innerHTML = summaryHTML;
}

// ============================================
// Result Actions
// ============================================
function downloadVideo() {
    if (!appState.uploadedFile) return;
    
    // Create download link
    const a = document.createElement('a');
    a.href = URL.createObjectURL(appState.uploadedFile);
    a.download = `processed_${appState.uploadedFile.name}`;
    a.click();
    
    addProcessingLog('Video downloaded successfully');
}

function processAnother() {
    // Reset state
    appState.selectedWorkflow = null;
    appState.uploadedFile = null;
    appState.processingOptions = {};
    appState.currentStep = 0;
    
    // Reset UI
    hideSection('upload-section');
    hideSection('options-section');
    hideSection('processing-section');
    hideSection('results-section');
    hideSection('videoPreview');
    hideSection('fileInfo');
    
    // Clear file input
    const fileInput = document.getElementById('fileInput');
    if (fileInput) {
        fileInput.value = '';
    }
    
    // Clear workflow selection
    document.querySelectorAll('.workflow-card').forEach(card => {
        card.classList.remove('selected');
    });
    
    // Scroll to top
    scrollToElement('home');
}

// ============================================
// UI Helper Functions
// ============================================
function showSection(sectionId) {
    const section = document.getElementById(sectionId);
    if (section) {
        section.classList.remove('hidden');
        section.classList.add('fade-in');
    }
}

function hideSection(sectionId) {
    const section = document.getElementById(sectionId);
    if (section) {
        section.classList.add('hidden');
    }
}

function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}

function formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);
    
    if (hours > 0) {
        return `${hours}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
}

// ============================================
// Additional Event Listeners
// ============================================
function setupEventListeners() {
    // Prevent default drag behavior on document
    document.addEventListener('dragover', (e) => e.preventDefault());
    document.addEventListener('drop', (e) => e.preventDefault());
    
    // Update range slider display
    const summaryLengthSlider = document.getElementById('summary-length');
    if (summaryLengthSlider) {
        summaryLengthSlider.addEventListener('input', function() {
            // You can add visual feedback here if needed
        });
    }
}

// ============================================
// Console Welcome Message
// ============================================
console.log('%c🎬 ReelMaker-AI', 'font-size: 24px; font-weight: bold; color: #6366f1;');
console.log('%cAI-Powered Video Processing Platform', 'font-size: 14px; color: #8b5cf6;');
console.log('Ready to transform your videos! 🚀');

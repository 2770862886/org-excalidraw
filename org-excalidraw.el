;;; org-excalidraw.el --- Excalidraw integration for Org mode -*- lexical-binding: t; -*-

;; Author: 2770862886
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.3"))
;; Keywords: multimedia, org, drawing
;; URL: https://github.com/psibot/org-excalidraw

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; Provides Excalidraw integration for Org mode with a custom `excalidraw:'
;; link type.
;;
;; Features:
;; - Custom `excalidraw:' link type: [[excalidraw:uuid.excalidraw]]
;; - Inline SVG image display in Org buffers (via advice on
;;   `org-display-inline-images')
;; - Auto-export .excalidraw to .svg on file change (via `filenotify')
;; - Open .excalidraw source files with system application
;; - Export support for HTML and LaTeX backends
;;
;; Prerequisites:
;; - `excalidraw_export' CLI tool (npm install -g excalidraw_export)
;;
;; Usage:
;;   (require 'org-excalidraw)
;;   (setq org-excalidraw-directory "~/draws")
;;   (org-excalidraw-setup)
;;
;; Interactive commands:
;;   `org-excalidraw-create-drawing' - Create a new drawing and insert link
;;   `org-excalidraw-export-all'     - Batch export all .excalidraw to SVG

;;; Code:

(require 'org)
(require 'org-id)
(require 'org-element)

;;;; Customization

(defgroup org-excalidraw nil
  "Excalidraw integration for Org mode."
  :group 'org
  :prefix "org-excalidraw-")

(defcustom org-excalidraw-directory "~/draws"
  "Directory to store excalidraw files."
  :type 'directory
  :group 'org-excalidraw)

(defcustom org-excalidraw-image-width 800
  "Default display width (in pixels) for excalidraw inline images.
Can be overridden per-image with #+ATTR_ORG: :width VALUE.
Set to nil to use the image's actual size."
  :type '(choice (integer :tag "Width in pixels")
                 (const :tag "Actual size" nil))
  :group 'org-excalidraw)

(defcustom org-excalidraw-export-command "excalidraw_export --rename_fonts=true"
  "Shell command to export .excalidraw files to SVG.
The excalidraw file path will be appended as an argument."
  :type 'string
  :group 'org-excalidraw)

(defcustom org-excalidraw-open-command
  (cond
   ((eq system-type 'darwin) "open")
   ((eq system-type 'gnu/linux) "xdg-open")
   ((memq system-type '(cygwin windows-nt ms-dos)) "start")
   (t "xdg-open"))
  "System command to open .excalidraw files for editing."
  :type 'string
  :group 'org-excalidraw)

(defcustom org-excalidraw-file-watch-p t
  "If non-nil, watch `org-excalidraw-directory' for file changes
and auto-export modified .excalidraw files to SVG."
  :type 'boolean
  :group 'org-excalidraw)

(defvar org-excalidraw-base
  "{
  \"type\": \"excalidraw\",
  \"version\": 2,
  \"source\": \"https://excalidraw.com\",
  \"elements\": [],
  \"appState\": {
    \"gridSize\": null,
    \"viewBackgroundColor\": \"#ffffff\"
  },
  \"files\": {}
}"
  "JSON template for new excalidraw files.")

(defvar org-excalidraw--file-watcher nil
  "File watcher descriptor for `org-excalidraw-directory'.")

;;;; Internal helpers

(defun org-excalidraw--to-svg (path)
  "Export excalidraw file at PATH to SVG."
  (let ((cmd (concat org-excalidraw-export-command " "
                     (shell-quote-argument path))))
    (shell-command cmd)))

(defun org-excalidraw--open (path)
  "Open excalidraw file at PATH with system application."
  (let ((cmd (concat org-excalidraw-open-command " "
                     (shell-quote-argument path))))
    (shell-command cmd)))

(defun org-excalidraw--svg-path (excalidraw-path)
  "Return the SVG file path for EXCALIDRAW-PATH.
EXCALIDRAW-PATH can be relative (resolved against
`org-excalidraw-directory') or absolute."
  (let ((full (if (file-name-absolute-p excalidraw-path)
                  excalidraw-path
                (expand-file-name excalidraw-path org-excalidraw-directory))))
    (concat full ".svg")))

;;;; Custom link type

(defun org-excalidraw--follow (path _)
  "Follow an excalidraw: link -- open the .excalidraw source file."
  (let ((full-path (expand-file-name path org-excalidraw-directory)))
    (if (file-exists-p full-path)
        (org-excalidraw--open full-path)
      (user-error "Excalidraw file not found: %s" full-path))))

(defun org-excalidraw--export (path desc backend _info)
  "Export an excalidraw: link for BACKEND."
  (let* ((svg (org-excalidraw--svg-path path))
         (width (or org-excalidraw-image-width 800)))
    (cond
     ((org-export-derived-backend-p backend 'html)
      (format "<img src=\"%s\" alt=\"%s\" style=\"max-width:%dpx;width:100%%;\">"
              svg (or desc path) width))
     ((org-export-derived-backend-p backend 'latex)
      (format "\\includegraphics[width=\\linewidth]{%s}" svg))
     (t (or desc path)))))

;;;; Inline image display

(defun org-excalidraw--image-width (link)
  "Determine display width for an excalidraw LINK.
Checks #+ATTR_ORG :width first, then falls back to
`org-excalidraw-image-width'."
  (let* ((par (org-element-lineage link 'paragraph))
         (attr-width (and par
                          (ignore-errors
                            (require 'ox)
                            (org-export-read-attribute :attr_org par :width)))))
    (cond
     ((and (stringp attr-width)
           (string-match-p "\\`[0-9]+\\'" attr-width))
      (string-to-number attr-width))
     ((numberp org-excalidraw-image-width)
      org-excalidraw-image-width)
     (t nil))))

(defun org-excalidraw--display-inline-images (&optional _include-linked refresh beg end)
  "Display inline images for excalidraw: links.
Intended as an :after advice for `org-display-inline-images'."
  (when (display-graphic-p)
    (let ((beg (or beg (point-min)))
          (end (or end (point-max)))
          (re "\\[\\[excalidraw:\\([^]]+\\)\\]"))
      (org-with-point-at beg
        (while (re-search-forward re end t)
          (let* ((link (org-element-lineage
                        (save-match-data (org-element-context))
                        'link t))
                 (path (when link (org-element-property :path link)))
                 (svg-path (when path (org-excalidraw--svg-path path)))
                 (old (when link
                        (get-char-property-and-overlay
                         (org-element-begin link)
                         'org-image-overlay))))
            (when (and svg-path (file-exists-p svg-path))
              (if (and (car-safe old) refresh)
                  (image-flush (overlay-get (cdr old) 'display))
                (unless (car-safe old)
                  (let* ((width (org-excalidraw--image-width link))
                         (image (org--create-inline-image svg-path width)))
                    (when image
                      (let ((ov (make-overlay
                                 (org-element-begin link)
                                 (progn
                                   (goto-char (org-element-end link))
                                   (unless (eolp) (skip-chars-backward " \t"))
                                   (point)))))
                        (image-flush image)
                        (overlay-put ov 'display image)
                        (overlay-put ov 'face 'default)
                        (overlay-put ov 'org-image-overlay t)
                        (overlay-put ov 'modification-hooks
                                     (list 'org-display-inline-remove-overlay))
                        (when (boundp 'image-map)
                          (overlay-put ov 'keymap image-map))
                        (push ov org-inline-image-overlays)))))))))))))

;;;; File watching

(defun org-excalidraw--handle-file-change (event)
  "Handle file change EVENT, auto-export .excalidraw to SVG."
  (let* ((event-type (cadr event))
         (filename (pcase event-type
                     ('renamed (cadddr event))
                     (_ (caddr event)))))
    (when (and filename
               (stringp filename)
               (string-suffix-p ".excalidraw" filename)
               (not (string-suffix-p ".excalidraw.svg" filename))
               (file-exists-p filename))
      (message "org-excalidraw: auto-exporting %s..." (file-name-nondirectory filename))
      (org-excalidraw--to-svg filename))))

;;;; Interactive commands

;;;###autoload
(defun org-excalidraw-create-drawing ()
  "Create a new excalidraw drawing and insert an excalidraw: link."
  (interactive)
  (let* ((filename (format "%s.excalidraw" (org-id-uuid)))
         (path (expand-file-name filename org-excalidraw-directory)))
    (unless (file-directory-p org-excalidraw-directory)
      (make-directory org-excalidraw-directory t))
    (with-temp-file path (insert org-excalidraw-base))
    (org-excalidraw--to-svg path)
    (insert (format "[[excalidraw:%s]]" filename))
    (org-excalidraw--open path)))

;;;###autoload
(defun org-excalidraw-export-all ()
  "Export all .excalidraw files in `org-excalidraw-directory' to SVG."
  (interactive)
  (let* ((files (directory-files org-excalidraw-directory t "\\.excalidraw$"))
         (count 0))
    (dolist (f files)
      (unless (string-suffix-p ".excalidraw.svg" f)
        (message "Exporting %s..." (file-name-nondirectory f))
        (org-excalidraw--to-svg f)
        (setq count (1+ count))))
    (message "org-excalidraw: exported %d files." count)))

;;;; Setup / Teardown

;;;###autoload
(defun org-excalidraw-setup ()
  "Initialize org-excalidraw integration.
Register the `excalidraw:' link type, add inline image display
advice, and optionally start file watching."
  (interactive)
  ;; Register custom link type
  (org-link-set-parameters "excalidraw"
                           :follow #'org-excalidraw--follow
                           :export #'org-excalidraw--export)
  ;; Advice for inline image display
  (advice-add 'org-display-inline-images :after
              #'org-excalidraw--display-inline-images)
  ;; File watching
  (when org-excalidraw-file-watch-p
    (require 'filenotify nil t)
    (when (and (fboundp 'file-notify-add-watch)
               (file-directory-p org-excalidraw-directory))
      (setq org-excalidraw--file-watcher
            (file-notify-add-watch org-excalidraw-directory
                                   '(change)
                                   #'org-excalidraw--handle-file-change))))
  (message "org-excalidraw: initialized."))

(defun org-excalidraw-teardown ()
  "Remove org-excalidraw integration.
Remove advice and stop file watching."
  (interactive)
  (advice-remove 'org-display-inline-images
                 #'org-excalidraw--display-inline-images)
  (when (and org-excalidraw--file-watcher
             (fboundp 'file-notify-rm-watch))
    (file-notify-rm-watch org-excalidraw--file-watcher)
    (setq org-excalidraw--file-watcher nil))
  (message "org-excalidraw: deactivated."))

(provide 'org-excalidraw)
;;; org-excalidraw.el ends here

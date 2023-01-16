;; -*- lexical-binding: t; -*-
(require 'transient)
(require 'seq)

(defvar ffmpeg-crop-infiles nil)
(defvar ffmpeg-crop-description "")

;; Infixes

(transient-define-argument ffmpeg-crop--i ()
  "Input file"
  :class 'transient-option
  :key "i"
  :argument "-i "
  :always-read t
  :init-value (lambda (obj) (oset obj value (car ffmpeg-crop-infiles)))
  :description "Input file"
  :prompt "Input video: "
  :reader 'ffmpeg-crop--read-file)

(defun ffmpeg-crop--read-file (prompt initial-input history)
  (interactive)
  (read-file-name prompt default-directory nil t initial-input nil))

(transient-define-argument ffmpeg-crop--vf ()
  "Ending at time"
  :class 'transient-option
  :key "-vf"
  :argument "-vf "
  :init-value (lambda (obj) (oset obj value "scale='trunc(iw/2):trunc(ih/2)'"))
  :description "Video filter")

(transient-define-infix ffmpeg-crop--add-description ()
  :description "Video description"
  :class 'transient-lisp-variable
  :variable 'ffmpeg-crop-description
  :reader '(lambda (prompt initial history)
             (interactive)
            (read-from-minibuffer prompt initial nil nil history)))

(defun ffmpeg-crop--read-time (prompt initial-input history)
  (interactive)
  (read-from-minibuffer prompt nil nil nil history))

;; Suffixes

(transient-define-suffix ffmpeg-crop--copy ()
  (interactive)
  (message "%s" (transient-args 'ffmpeg-crop)))

(transient-define-suffix ffmpeg-crop--next ()
  "Cancel this file and operate on the next one."
  (interactive)
  (setq ffmpeg-crop-description "")
  (when-let ((infiles (cdr-safe ffmpeg-crop-infiles)))
    (ffmpeg-crop infiles)))

(transient-define-suffix ffmpeg-crop--run (&optional args)
  "Call ffmpeg and convert this file"
  (interactive (list (transient-args 'ffmpeg-crop)))
  (let* ((infile (seq-some (lambda (arg) (when (string-prefix-p "-i " arg)
                                      (substring arg 3)))
                           args))
         (outfile (replace-regexp-in-string
                   "\\.mp4$"
                   (concat "_small"
                           (if (and ffmpeg-crop-description
                                    (> (length ffmpeg-crop-description) 0))
                               (concat "_" 
                                       (string-join
                                        (split-string ffmpeg-crop-description)
                                        "_"))
                             "")
                           ".mp4")
                   infile))
         (ffmpeg-proc 
          
          (apply #'start-process
                 "ffmpeg" "ffmpeg-crop" "/usr/bin/ffmpeg"
                 (append (mapcan (lambda (arg)
                                   (string-match "^\\([^[:space:]]+\\) \\(.*\\)" arg)
                                   (list (match-string 1 arg) (match-string 2 arg)))
                                 args)
                         (list "-an" (expand-file-name outfile))))))
    (set-process-sentinel
     ffmpeg-proc
     (lambda (proc event)
       (if (eq 'exit (process-status proc))
           (message "Converted: %s" outfile)
         (message "Failed to convert: %s"outfile))))
    (ffmpeg-crop--next)))

;; Prefix commands

;;;###autoload
(transient-define-prefix ffmpeg-crop (infiles)
  "Downsample a video and process it."
  ["Input File"
   (ffmpeg-crop--i)
   ("h" ffmpeg-crop--add-description)]
  [["Times"
    ("ss" "From time " "-ss " :class transient-option)
    ("to" "Until time" "-to " :class transient-option)]
   ["Filter"
    ("vf" ffmpeg-crop--vf)]]
  ["Convert"
   [("RET" "Convert" ffmpeg-crop--run)
    ("w" "Copy cmd" ffmpeg-crop--copy :transient t)]
   [("n" "Next file" ffmpeg-crop--next :if (lambda () (cdr ffmpeg-crop-infiles)))]]
  (interactive (list (completing-read-multiple
                      "Videos: "
                      #'completion--file-name-table
                      nil t (abbreviate-file-name default-directory))))
  (setq ffmpeg-crop-infiles infiles)
  (let ((infile (car infiles)))
    (start-process (concat "mpv " (file-name-base infile))
                   (concat "mpv " (file-name-base infile))
                   "/usr/bin/mpv" "--osd-level=3" "--mute=yes"
                   (expand-file-name infile)))
  (transient-setup 'ffmpeg-crop))

;;;###autoload
(defun ffmpeg-crop-dired ()
  (interactive)
  (require 'dired)
  (ffmpeg-crop (dired-get-marked-files)))

(provide 'ffmpeg-crop)

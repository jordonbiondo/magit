;;; magit-autorevert.el --- revert buffers when files in repository change  -*- lexical-binding: t -*-

;; Copyright (C) 2010-2016  The Magit Project Contributors
;;
;; You should have received a copy of the AUTHORS.md file which
;; lists all contributors.  If not, see http://magit.vc/authors.

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Maintainer: Jonas Bernoulli <jonas@bernoul.li>

;; Magit is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Magit is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Magit.  If not, see http://www.gnu.org/licenses.

;;; Code:

(require 'cl-lib)
(require 'dash)

(require 'magit-git)

(require 'autorevert)

(defgroup magit-auto-revert nil
  "Revert buffers when files in repository change."
  :group 'auto-revert
  :group 'magit-extensions)

(defcustom magit-auto-revert-tracked-only t
  "Whether `magit-auto-revert-mode' only reverts tracked files."
  :package-version '(magit . "2.4.0")
  :group 'magit-auto-revert
  :type 'boolean
  :set (lambda (var val)
         (set var val)
         (when (and (bound-and-true-p magit-auto-revert-mode)
                    (featurep 'magit-autorevert))
           (magit-auto-revert-mode -1)
           (magit-auto-revert-mode))))

(defcustom magit-auto-revert-immediately (not file-notify--library)
  "Whether Magit reverts buffers immediately.

If this is non-nil and either `global-auto-revert-mode' or
`magit-auto-revert-mode' is enabled, then Magit immediately
reverts buffers by explicitly calling `auto-revert-buffers'
after running git for side-effects.

If `auto-revert-use-notify' is non-nil (and file notifications
are actually supported), then `magit-auto-revert-immediately'
does not have to be non-nil, because the reverts happen
immediately anyway.

If `magit-auto-revert-immediately' and `auto-revert-use-notify'
are both nil, then reverts happen after `auto-revert-interval'
seconds of user inactivity.  That is not desirable."
  :package-version '(magit . "2.4.0")
  :group 'magit-auto-revert
  :type 'boolean)

(defun magit-turn-on-auto-revert-mode-if-desired (&optional file)
  (if file
      (--when-let (find-buffer-visiting file)
        (with-current-buffer it
          (magit-turn-on-auto-revert-mode-if-desired)))
    (when (and buffer-file-name
               (file-readable-p buffer-file-name)
               (magit-toplevel)
               (or (not magit-auto-revert-tracked-only)
                   (magit-file-tracked-p buffer-file-name)))
      (auto-revert-mode))))

;;;###autoload
(defvar magit-revert-buffers t)
(make-obsolete-variable 'magit-revert-buffers 'magit-auto-revert-mode
                        "Magit 2.4.0")

;;;###autoload
(define-globalized-minor-mode magit-auto-revert-mode auto-revert-mode
  magit-turn-on-auto-revert-mode-if-desired
  :package-version '(magit . "2.4.0")
  :group 'magit
  :group 'magit-auto-revert
  ;; When `global-auto-revert-mode' is enabled, then this mode is
  ;; redundant.  When `magit-revert-buffers' is nil, then the user has
  ;; opted out of the automatic reverts while the old implementation
  ;; was still in use.  In all other cases enable the mode because if
  ;; buffers are not automatically reverted that would make many very
  ;; common tasks much more cumbersome.
  :init-value (and (not global-auto-revert-mode) magit-revert-buffers))

;; `:init-value t' only sets the value of the mode variable
;; but does not cause the mode function to be called.
(cl-eval-when (load eval)
  (when magit-auto-revert-mode
    (magit-auto-revert-mode)))

;; If the user has set the obsolete `magit-revert-buffers' to nil
;; after loading magit, then we should still respect that setting.
(defun magit-auto-revert-mode--maybe-turn-off-after-init ()
  (unless magit-revert-buffers
    (magit-auto-revert-mode -1)))
(unless after-init-time
  (add-hook 'after-init-hook
            #'magit-auto-revert-mode--maybe-turn-off-after-init t))

(put 'magit-auto-revert-mode 'function-documentation
     "Toggle Magit Auto Revert mode.
With a prefix argument ARG, enable Magit Auto Revert mode if ARG
is positive, and disable it otherwise.  If called from Lisp,
enable the mode if ARG is omitted or nil.

Magit Auto Revert mode is a global minor mode that reverts
buffers associated with a file that is located inside a Git
repository when the file changes on disk.  Use `auto-revert-mode'
to revert a particular buffer.  Or use `global-auto-revert-mode'
to revert all file-visiting buffers, not just those that visit
a file located inside a Git repository.

This global mode works by turning on the buffer-local mode
`auto-revert-mode' at the time a buffer is first created.  The
local mode is turned on if the visited file is being tracked in
a Git repository at the time when the buffer is created.

If `magit-auto-revert-tracked-only' is non-nil (the default),
then only tracked files are reverted.  But if you stage a
previously untracked file using `magit-stage', then this mode
notices that.

Unlike `global-auto-revert-mode', this mode never reverts any
buffers that are not visiting files.

The behavior of this mode can be customized using the options
in the `autorevert' and `magit-autorevert' groups.

This function calls the hook `magit-auto-revert-mode-hook'.")

(defun magit-auto-revert-buffers ()
  (when (and magit-auto-revert-immediately
             (or global-auto-revert-mode
                 (and magit-auto-revert-mode auto-revert-buffer-list)))
    (auto-revert-buffers)))

(defun auto-revert-buffers ()
  "Revert buffers as specified by Auto-Revert and Global Auto-Revert Mode.

Should `global-auto-revert-mode' be active all file buffers are checked.

Should `auto-revert-mode' be active in some buffers, those buffers
are checked.

Non-file buffers that have a custom `revert-buffer-function' and
`buffer-stale-function' are reverted either when Auto-Revert
Mode is active in that buffer, or when the variable
`global-auto-revert-non-file-buffers' is non-nil and Global
Auto-Revert Mode is active.

This function stops whenever there is user input.  The buffers not
checked are stored in the variable `auto-revert-remaining-buffers'.

To avoid starvation, the buffers in `auto-revert-remaining-buffers'
are checked first the next time this function is called.

This function is also responsible for removing buffers no longer in
Auto-Revert mode from `auto-revert-buffer-list', and for canceling
the timer when no buffers need to be checked."
  (save-match-data
    (let ((bufs (if global-auto-revert-mode
		    (buffer-list)
		  auto-revert-buffer-list))
	  remaining new)
      ;; Partition `bufs' into two halves depending on whether or not
      ;; the buffers are in `auto-revert-remaining-buffers'.  The two
      ;; halves are then re-joined with the "remaining" buffers at the
      ;; head of the list.
      (dolist (buf auto-revert-remaining-buffers)
	(if (memq buf bufs)
	    (push buf remaining)))
      (dolist (buf bufs)
	(if (not (memq buf remaining))
	    (push buf new)))
      (setq bufs (nreverse (nconc new remaining)))
      (while (and bufs
		  (not (and auto-revert-stop-on-user-input
			    (input-pending-p))))
	(let ((buf (car bufs)))
          (if (buffer-live-p buf)
	      (with-current-buffer buf
		;; Test if someone has turned off Auto-Revert Mode in a
		;; non-standard way, for example by changing major mode.
		(if (and (not auto-revert-mode)
			 (not auto-revert-tail-mode)
			 (memq buf auto-revert-buffer-list))
		    (setq auto-revert-buffer-list
			  (delq buf auto-revert-buffer-list)))
		(when (auto-revert-active-p)
		  ;; Enable file notification.
		  (when (and auto-revert-use-notify buffer-file-name
			     (not auto-revert-notify-watch-descriptor))
		    (auto-revert-notify-add-watch))
		  (auto-revert-handler)))
	    ;; Remove dead buffer from `auto-revert-buffer-list'.
	    (setq auto-revert-buffer-list
		  (delq buf auto-revert-buffer-list))))
	(setq bufs (cdr bufs)))
      (setq auto-revert-remaining-buffers bufs)
      ;; Check if we should cancel the timer.
      (when (and (not global-auto-revert-mode)
		 (null auto-revert-buffer-list))
	(cancel-timer auto-revert-timer)
	(setq auto-revert-timer nil)))))

(custom-add-to-group 'magit 'auto-revert-check-vc-info 'custom-variable)

;;; magit-autorevert.el ends soon
(provide 'magit-autorevert)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; magit-autorevert.el ends here

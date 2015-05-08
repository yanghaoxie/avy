;;; avy.el --- set-based completion -*- lexical-binding: t -*-

;; Copyright (C) 2015  Free Software Foundation, Inc.

;; Author: Oleh Krehel

;; This file is part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This package provides a generic completion method based on building
;; a balanced decision tree with each candidate being a leaf. To
;; traverse the tree from the root to a desired leaf, typically a
;; sequence of `read-char' can be used.
;;
;; In order for `read-char' to make sense, the tree needs to be
;; visualized appropriately, with a character at each branch node. So
;; this completion method works only for things that you can see on
;; your screen, all at once:
;;
;; * character positions
;; * word or subword start positions
;; * line beginning positions
;; * link positions
;; * window positions
;;
;; If you're familiar with the popular `ace-jump-mode' package, this
;; package does all that and more, without the implementation
;; headache.

;;; Code:
(require 'cl-lib)

(defmacro avy-multipop (lst n)
  "Remove LST's first N elements and return them."
  `(if (<= (length ,lst) ,n)
       (prog1 ,lst
         (setq ,lst nil))
     (prog1 ,lst
       (setcdr
        (nthcdr (1- ,n) (prog1 ,lst (setq ,lst (nthcdr ,n ,lst))))
        nil))))

(defun avy-tree (lst keys)
  "Coerce LST into a balanced tree.
The degree of the tree is the length of KEYS.
KEYS are placed appropriately on internal nodes."
  (let ((len (length keys)))
    (cl-labels
        ((rd (ls)
           (let ((ln (length ls)))
             (if (< ln len)
                 (cl-pairlis keys
                             (mapcar (lambda (x) (cons 'leaf x)) ls))
               (let ((ks (copy-sequence keys))
                     res)
                 (dolist (s (avy-subdiv ln len))
                   (push (cons (pop ks)
                               (if (eq s 1)
                                   (cons 'leaf (pop ls))
                                 (rd (avy-multipop ls s))))
                         res))
                 (nreverse res))))))
      (rd lst))))

(defun avy-subdiv (n b)
  "Distribute N in B terms in a balanced way."
  (let* ((p (1- (floor (+ (log n b) 1e-6))))
         (x1 (expt b p))
         (x2 (* b x1))
         (delta (- n x2))
         (n2 (/ delta (- x2 x1)))
         (n1 (- b n2 1)))
    (append
     (make-list n1 x1)
     (list
      (- n (* n1 x1) (* n2 x2)))
     (make-list n2 x2))))

(defun avy-traverse (tree walker &optional recur-key)
  "Traverse TREE generated by `avy-tree'.
WALKER is a function that takes KEYS and LEAF.

RECUR-KEY is used in recursion.

LEAF is a member of LST argument of `avy-tree'.

KEYS is the path from the root of `avy-tree' to LEAF."
  (dolist (br tree)
    (let ((key (cons (car br) recur-key)))
      (if (eq (cadr br) 'leaf)
          (funcall walker key (cddr br))
        (avy-traverse (cdr br) walker key)))))

(defun avy-read (tree display-fn cleanup-fn)
  "Select a leaf from TREE using consecutive `read-char'.

DISPLAY-FN should take CHAR and LEAF and signify that LEAFs
associated with CHAR will be selected if CHAR is pressed.  This is
commonly done by adding a CHAR overlay at LEAF position.

CLEANUP-FN should take no arguments and remove the effects of
multiple DISPLAY-FN invokations."
  (catch 'done
    (while tree
      (avy-traverse tree display-fn)
      (let ((char (read-char))
            branch)
        (funcall cleanup-fn)
        (if (setq branch (assoc char tree))
            (if (eq (car (setq tree (cdr branch))) 'leaf)
                (throw 'done (cdr tree)))
          (signal 'user-error (list "No such candidate" char))
          (throw 'done nil))))))

(provide 'avy)

;;; avy.el ends here

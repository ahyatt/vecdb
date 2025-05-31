;;; embed-sqlite.el --- Embed SQLite database in Emacs Lisp -- lexical-binding: t; -*-

;; Copyright (c) 2025  Freed Software Foundation, Inc.

;; Author: Andrew Hyatt <ahyatt@gmail.com>
;; Homepage: https://github.com/ahyatt/embed-db
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; This package provides a way to store embeddings in a SQLite database in Emacs
;; Lisp.

;;; Code:

(require 'sqlite)
(require 'embed-db)
(require 'cl-lib)

(defvar embed-sqlite-connections (make-hash-table :test 'equal)
  "Hash table to store SQLite database connections by collection name.")

(cl-defstruct (embed-sqlite-provider (:include embed-db-provider
                                               (name "sqlite-vec")))
  dir)

(cl-defmethod embed-db-create ((provider embed-sqlite-provider)
                               (collection embed-db-collection))
  "Create a new SQLite database for embeddings."
  (let* ((db-file (concat (embed-sqlite-provider-dir provider)
                          "/"
                          (embed-db-collection-name collection)))
         (connection (or (gethash (embed-db-collection-name collection)
                                  embed-sqlite-connections)
                         (if (file-exists-p db-file)
                             (error "Database file already exists: %s" db-file)
                           (let ((connection (sqlite-open db-file)))
                             (puthash (embed-db-collection-name collection)
                                      connection
                                      embed-sqlite-connections)
                             connection)))))
    (sqlite-execute connection ".load ./vec0")
    (let ((schema (embed-db-collection-db-fields collection)))
      (sqlite-transaction connection)
      (sqlite-exec connction
                   (funcall #'concat
                            (append '("CREATE TABLE embedding_and_payloads ("
                                      "  id UINT64 PRIMARY KEY,")
                                    (mapconcat (lambda (field)
                                                 (format "  %s %s," (car field) (pcase (cdr field)
                                                                                  ('integer "INTEGER")
                                                                                  ('float "REAL")
                                                                                  ('string "TEXT")
                                                                                  ('binary "BLOB"))))
                                               (embed-db-collection-payload-fields collection))
                                    '("  embedding BLOB"
                                      ");"))))
      (sqlite-exec connection
                   "CREATE VIRTUAL TABLE embeddings USING vec0(embedding float[?])"
                   (embed-db-collection-vector-size collection))
      (sqlite-commit connection))
    (sqlite-exec db-file
                 "CREATE INDEX IF NOT EXISTS idx_embeddings_vector ON embeddings(vector")))


(provide 'embed-sqlite)

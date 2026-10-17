export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          auth_user_id: string | null
          created_at: string
          email: string | null
          id: string
          provider: string
          provider_subject: string
          role: string
          teacher_id: string | null
          updated_at: string
        }
        Insert: {
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          id?: string
          provider: string
          provider_subject: string
          role?: string
          teacher_id?: string | null
          updated_at?: string
        }
        Update: {
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          id?: string
          provider?: string
          provider_subject?: string
          role?: string
          teacher_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounts_teacher_id_fkey"
            columns: ["teacher_id"]
            isOneToOne: false
            referencedRelation: "teachers"
            referencedColumns: ["id"]
          },
        ]
      }
      assets: {
        Row: {
          checksum: string | null
          content_type: string
          created_at: string
          delete_requested_at: string | null
          file_name: string
          final_key: string
          id: string
          owner_account_id: string
          purpose: string
          ready_at: string | null
          size_bytes: number
          staging_key: string
          staging_version_id: string
          status: string
          upload_batch_id: string | null
          version_id: string | null
        }
        Insert: {
          checksum?: string | null
          content_type: string
          created_at?: string
          delete_requested_at?: string | null
          file_name: string
          final_key: string
          id?: string
          owner_account_id: string
          purpose: string
          ready_at?: string | null
          size_bytes: number
          staging_key: string
          staging_version_id: string
          status?: string
          upload_batch_id?: string | null
          version_id?: string | null
        }
        Update: {
          checksum?: string | null
          content_type?: string
          created_at?: string
          delete_requested_at?: string | null
          file_name?: string
          final_key?: string
          id?: string
          owner_account_id?: string
          purpose?: string
          ready_at?: string | null
          size_bytes?: number
          staging_key?: string
          staging_version_id?: string
          status?: string
          upload_batch_id?: string | null
          version_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assets_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assets_upload_batch_id_fkey"
            columns: ["upload_batch_id"]
            isOneToOne: false
            referencedRelation: "upload_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      assignments: {
        Row: {
          accept_after_solution: boolean
          close_at: string | null
          due_at: string
          full_score: number
          full_score_locked_at: string | null
          late_penalty_pct: number
          post_id: string
          reward_locked_at: string | null
          reward_tokens: number
        }
        Insert: {
          accept_after_solution?: boolean
          close_at?: string | null
          due_at: string
          full_score: number
          full_score_locked_at?: string | null
          late_penalty_pct?: number
          post_id: string
          reward_locked_at?: string | null
          reward_tokens?: number
        }
        Update: {
          accept_after_solution?: boolean
          close_at?: string | null
          due_at?: string
          full_score?: number
          full_score_locked_at?: string | null
          late_penalty_pct?: number
          post_id?: string
          reward_locked_at?: string | null
          reward_tokens?: number
        }
        Relationships: [
          {
            foreignKeyName: "assignments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: true
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
        ]
      }
      attachments: {
        Row: {
          asset_id: string
          created_at: string
          id: string
          position: number
          post_id: string | null
          solution_id: string | null
          submission_id: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string
          id?: string
          position: number
          post_id?: string | null
          solution_id?: string | null
          submission_id?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string
          id?: string
          position?: number
          post_id?: string | null
          solution_id?: string | null
          submission_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "attachments_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: true
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attachments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attachments_solution_id_fkey"
            columns: ["solution_id"]
            isOneToOne: false
            referencedRelation: "solutions"
            referencedColumns: ["assignment_id"]
          },
          {
            foreignKeyName: "attachments_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      b2_daily_usage: {
        Row: {
          class_b_requests: number
          copy_bytes: number
          day: string
          download_bytes: number
          source: string
          updated_at: string
        }
        Insert: {
          class_b_requests?: number
          copy_bytes?: number
          day: string
          download_bytes?: number
          source: string
          updated_at?: string
        }
        Update: {
          class_b_requests?: number
          copy_bytes?: number
          day?: string
          download_bytes?: number
          source?: string
          updated_at?: string
        }
        Relationships: []
      }
      backup_runs: {
        Row: {
          detail: string | null
          dump_name: string | null
          file_count: number | null
          finished_at: string | null
          id: string
          kind: string
          new_file_count: number | null
          started_at: string
          status: string
          total_bytes: number | null
        }
        Insert: {
          detail?: string | null
          dump_name?: string | null
          file_count?: number | null
          finished_at?: string | null
          id?: string
          kind: string
          new_file_count?: number | null
          started_at?: string
          status: string
          total_bytes?: number | null
        }
        Update: {
          detail?: string | null
          dump_name?: string | null
          file_count?: number | null
          finished_at?: string | null
          id?: string
          kind?: string
          new_file_count?: number | null
          started_at?: string
          status?: string
          total_bytes?: number | null
        }
        Relationships: []
      }
      classrooms: {
        Row: {
          created_at: string
          description: string | null
          id: string
          join_code: string
          join_enabled: boolean
          name: string
          teacher_id: string
          term_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          join_code: string
          join_enabled?: boolean
          name: string
          teacher_id: string
          term_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          join_code?: string
          join_enabled?: boolean
          name?: string
          teacher_id?: string
          term_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "classrooms_teacher_id_fkey"
            columns: ["teacher_id"]
            isOneToOne: false
            referencedRelation: "teachers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "classrooms_term_id_fkey"
            columns: ["term_id"]
            isOneToOne: false
            referencedRelation: "terms"
            referencedColumns: ["id"]
          },
        ]
      }
      comments: {
        Row: {
          assignment_id: string
          author_account_id: string
          body: string | null
          created_at: string
          id: string
          retracted_at: string | null
          student_id: string
        }
        Insert: {
          assignment_id: string
          author_account_id: string
          body?: string | null
          created_at?: string
          id?: string
          retracted_at?: string | null
          student_id: string
        }
        Update: {
          assignment_id?: string
          author_account_id?: string
          body?: string | null
          created_at?: string
          id?: string
          retracted_at?: string | null
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["post_id"]
          },
          {
            foreignKeyName: "comments_author_account_id_fkey"
            columns: ["author_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      grades: {
        Row: {
          applied_penalty_pct: number
          deduction: number | null
          graded_at: string
          graded_by_account_id: string
          graded_revision: number
          net_score: number | null
          override_comment_id: string | null
          passed: boolean
          penalty_override_pct: number | null
          raw_score: number | null
          submission_id: string
          timing: string
          timing_basis_at: string
          timing_due_at: string
          timing_i1: boolean
          version: number
        }
        Insert: {
          applied_penalty_pct: number
          deduction?: number | null
          graded_at: string
          graded_by_account_id: string
          graded_revision: number
          net_score?: number | null
          override_comment_id?: string | null
          passed: boolean
          penalty_override_pct?: number | null
          raw_score?: number | null
          submission_id: string
          timing: string
          timing_basis_at: string
          timing_due_at: string
          timing_i1: boolean
          version?: number
        }
        Update: {
          applied_penalty_pct?: number
          deduction?: number | null
          graded_at?: string
          graded_by_account_id?: string
          graded_revision?: number
          net_score?: number | null
          override_comment_id?: string | null
          passed?: boolean
          penalty_override_pct?: number | null
          raw_score?: number | null
          submission_id?: string
          timing?: string
          timing_basis_at?: string
          timing_due_at?: string
          timing_i1?: boolean
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "grades_graded_by_account_id_fkey"
            columns: ["graded_by_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grades_override_comment_id_fkey"
            columns: ["override_comment_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grades_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: true
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      memberships: {
        Row: {
          classroom_id: string
          joined_at: string
          student_id: string
        }
        Insert: {
          classroom_id: string
          joined_at?: string
          student_id: string
        }
        Update: {
          classroom_id?: string
          joined_at?: string
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_classroom_id_fkey"
            columns: ["classroom_id"]
            isOneToOne: false
            referencedRelation: "classrooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      posts: {
        Row: {
          body: string | null
          classroom_id: string
          content_updated_at: string | null
          id: string
          kind: string
          published_at: string
          title: string
          version: number
        }
        Insert: {
          body?: string | null
          classroom_id: string
          content_updated_at?: string | null
          id?: string
          kind: string
          published_at?: string
          title: string
          version?: number
        }
        Update: {
          body?: string | null
          classroom_id?: string
          content_updated_at?: string | null
          id?: string
          kind?: string
          published_at?: string
          title?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "posts_classroom_id_fkey"
            columns: ["classroom_id"]
            isOneToOne: false
            referencedRelation: "classrooms"
            referencedColumns: ["id"]
          },
        ]
      }
      revision_permissions: {
        Row: {
          id: string
          opened_at: string
          opened_by_account_id: string
          revoked_at: string | null
          status: string
          submission_id: string
          used_at: string | null
          used_revision: number | null
        }
        Insert: {
          id?: string
          opened_at?: string
          opened_by_account_id: string
          revoked_at?: string | null
          status?: string
          submission_id: string
          used_at?: string | null
          used_revision?: number | null
        }
        Update: {
          id?: string
          opened_at?: string
          opened_by_account_id?: string
          revoked_at?: string | null
          status?: string
          submission_id?: string
          used_at?: string | null
          used_revision?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "revision_permissions_opened_by_account_id_fkey"
            columns: ["opened_by_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revision_permissions_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      roster_entries: {
        Row: {
          created_at: string
          group_name: string
          id: string
          roll_number: number
          student_id: string
          term_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          group_name: string
          id?: string
          roll_number: number
          student_id: string
          term_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          group_name?: string
          id?: string
          roll_number?: number
          student_id?: string
          term_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "roster_entries_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "roster_entries_term_id_fkey"
            columns: ["term_id"]
            isOneToOne: false
            referencedRelation: "terms"
            referencedColumns: ["id"]
          },
        ]
      }
      solutions: {
        Row: {
          assignment_id: string
          body: string | null
          created_at: string
          published_at: string | null
          updated_at: string
          version: number
        }
        Insert: {
          assignment_id: string
          body?: string | null
          created_at?: string
          published_at?: string | null
          updated_at?: string
          version?: number
        }
        Update: {
          assignment_id?: string
          body?: string | null
          created_at?: string
          published_at?: string | null
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "solutions_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: true
            referencedRelation: "assignments"
            referencedColumns: ["post_id"]
          },
        ]
      }
      storage_settings: {
        Row: {
          admin_warn_pct: number
          daily_view_budget_bytes: number
          daily_view_budget_requests: number
          hard_stop_margin_bytes: number
          quota_bytes: number
          singleton: boolean
          teacher_warn_pct: number
          updated_at: string
        }
        Insert: {
          admin_warn_pct?: number
          daily_view_budget_bytes?: number
          daily_view_budget_requests?: number
          hard_stop_margin_bytes: number
          quota_bytes: number
          singleton?: boolean
          teacher_warn_pct?: number
          updated_at?: string
        }
        Update: {
          admin_warn_pct?: number
          daily_view_budget_bytes?: number
          daily_view_budget_requests?: number
          hard_stop_margin_bytes?: number
          quota_bytes?: number
          singleton?: boolean
          teacher_warn_pct?: number
          updated_at?: string
        }
        Relationships: []
      }
      students: {
        Row: {
          account_id: string | null
          created_at: string
          display_name: string
          id: string
          name_prefix: string | null
          student_code: string
          updated_at: string
        }
        Insert: {
          account_id?: string | null
          created_at?: string
          display_name: string
          id?: string
          name_prefix?: string | null
          student_code: string
          updated_at?: string
        }
        Update: {
          account_id?: string | null
          created_at?: string
          display_name?: string
          id?: string
          name_prefix?: string | null
          student_code?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "students_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: true
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      submissions: {
        Row: {
          assignment_id: string
          content_revision: number
          first_after_solution: boolean
          first_submitted_at: string
          id: string
          last_submitted_at: string
          reward_granted: boolean
          student_id: string
        }
        Insert: {
          assignment_id: string
          content_revision?: number
          first_after_solution?: boolean
          first_submitted_at: string
          id?: string
          last_submitted_at: string
          reward_granted?: boolean
          student_id: string
        }
        Update: {
          assignment_id?: string
          content_revision?: number
          first_after_solution?: boolean
          first_submitted_at?: string
          id?: string
          last_submitted_at?: string
          reward_granted?: boolean
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "submissions_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["post_id"]
          },
          {
            foreignKeyName: "submissions_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      teachers: {
        Row: {
          created_at: string
          display_name: string
          id: string
        }
        Insert: {
          created_at?: string
          display_name: string
          id?: string
        }
        Update: {
          created_at?: string
          display_name?: string
          id?: string
        }
        Relationships: []
      }
      term_control: {
        Row: {
          ended_at: string | null
          epoch: number
          singleton: boolean
          started_at: string
          status: string
          term_id: string
          updated_at: string
        }
        Insert: {
          ended_at?: string | null
          epoch?: number
          singleton?: boolean
          started_at?: string
          status?: string
          term_id: string
          updated_at?: string
        }
        Update: {
          ended_at?: string | null
          epoch?: number
          singleton?: boolean
          started_at?: string
          status?: string
          term_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "term_control_term_id_fkey"
            columns: ["term_id"]
            isOneToOne: false
            referencedRelation: "terms"
            referencedColumns: ["id"]
          },
        ]
      }
      terms: {
        Row: {
          created_at: string
          ended_at: string | null
          id: string
          name: string
          started_at: string
          status: string
          superseded_at: string | null
        }
        Insert: {
          created_at?: string
          ended_at?: string | null
          id?: string
          name: string
          started_at?: string
          status?: string
          superseded_at?: string | null
        }
        Update: {
          created_at?: string
          ended_at?: string | null
          id?: string
          name?: string
          started_at?: string
          status?: string
          superseded_at?: string | null
        }
        Relationships: []
      }
      upload_batches: {
        Row: {
          base_version: number | null
          classroom_id: string | null
          created_at: string
          expires_at: string
          files: Json
          id: string
          owner_account_id: string
          post_id: string | null
          purpose: string
          reserved_bytes: number
          status: string
        }
        Insert: {
          base_version?: number | null
          classroom_id?: string | null
          created_at?: string
          expires_at: string
          files?: Json
          id?: string
          owner_account_id: string
          post_id?: string | null
          purpose: string
          reserved_bytes: number
          status?: string
        }
        Update: {
          base_version?: number | null
          classroom_id?: string | null
          created_at?: string
          expires_at?: string
          files?: Json
          id?: string
          owner_account_id?: string
          post_id?: string | null
          purpose?: string
          reserved_bytes?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "upload_batches_classroom_id_fkey"
            columns: ["classroom_id"]
            isOneToOne: false
            referencedRelation: "classrooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "upload_batches_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "upload_batches_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      admin_add_teacher: {
        Args: {
          p_email: string
          p_new_teacher_name?: string
          p_teacher_id?: string
        }
        Returns: Json
      }
      admin_b2_usage: { Args: never; Returns: Json }
      admin_remove_teacher: { Args: { p_allowlist_id: string }; Returns: Json }
      admin_teachers: { Args: never; Returns: Json }
      authorize_files: { Args: { p_asset_ids: string[] }; Returns: string[] }
      claim_identity: { Args: { p_ref: string }; Returns: Json }
      classroom_view: { Args: { p_classroom_id: string }; Returns: Json }
      commit_roster_import: {
        Args: {
          p_admin_mode?: boolean
          p_group_name: string
          p_request_key: string
          p_rows: Json
        }
        Returns: Json
      }
      copying_stale: { Args: { p_limit?: number }; Returns: Json }
      create_classroom: {
        Args: {
          p_admin_mode?: boolean
          p_description: string
          p_name: string
          p_request_key: string
          p_teacher_id?: string
        }
        Returns: Json
      }
      create_post: {
        Args: {
          p_admin_mode?: boolean
          p_classroom_id: string
          p_post: Json
          p_request_key: string
        }
        Returns: Json
      }
      create_upload_batch: {
        Args: {
          p_admin_mode?: boolean
          p_classroom_id: string
          p_files: Json
          p_post_id: string
          p_purpose: string
          p_request_key: string
        }
        Returns: Json
      }
      delete_asset_begin: { Args: { p_job_id: number }; Returns: Json }
      delete_asset_finish: { Args: { p_job_id: number }; Returns: boolean }
      ensure_account: { Args: never; Returns: Json }
      files_sign_begin: { Args: { p_asset_ids: string[] }; Returns: Json }
      grade_submission: {
        Args: {
          p_admin_mode?: boolean
          p_expected_version: number
          p_override_pct: number
          p_pass: boolean
          p_raw: number
          p_reason: string
          p_request_key: string
          p_seen_revision: number
          p_submission_id: string
        }
        Returns: Json
      }
      jobs_claim: { Args: { p_limit?: number }; Returns: Json }
      jobs_complete: {
        Args: { p_job_id: number; p_note?: string }
        Returns: boolean
      }
      jobs_fail: {
        Args: { p_error: string; p_job_id: number }
        Returns: string
      }
      jobs_maintenance: { Args: never; Returns: Json }
      join_classroom: { Args: { p_code: string }; Returns: Json }
      lookup_classroom: { Args: { p_code: string }; Returns: Json }
      my_classrooms: { Args: never; Returns: Json }
      my_work: { Args: { p_classroom_id?: string }; Returns: Json }
      ping: { Args: never; Returns: string }
      preview_roster_import: {
        Args: { p_admin_mode?: boolean; p_group_name: string; p_rows: Json }
        Returns: Json
      }
      rebind_preview: {
        Args: { p_admin_mode?: boolean; p_email: string; p_student_id: string }
        Returns: Json
      }
      rebind_student: {
        Args: { p_admin_mode?: boolean; p_email: string; p_student_id: string }
        Returns: Json
      }
      record_b2_usage: {
        Args: {
          p_bytes: number
          p_copy_bytes?: number
          p_requests: number
          p_source: string
        }
        Returns: undefined
      }
      remove_member: {
        Args: {
          p_admin_mode?: boolean
          p_classroom_id: string
          p_student_id: string
        }
        Returns: Json
      }
      roster_overview: { Args: { p_admin_mode?: boolean }; Returns: Json }
      search_roster: { Args: { p_query: string }; Returns: Json }
      set_join_enabled: {
        Args: {
          p_admin_mode?: boolean
          p_classroom_id: string
          p_enabled: boolean
        }
        Returns: Json
      }
      storage_status: { Args: never; Returns: Json }
      submission_status: { Args: { p_assignment_id: string }; Returns: Json }
      submit_assignment: {
        Args: {
          p_assignment_id: string
          p_expected_revision: number
          p_files: string[]
          p_request_key: string
        }
        Returns: Json
      }
      sweep_copying_finish: {
        Args: { p_asset_id: string; p_version_id: string }
        Returns: string
      }
      teacher_submission_list: {
        Args: { p_assignment_id: string }
        Returns: Json
      }
      teacher_work_summary: { Args: { p_classroom_id: string }; Returns: Json }
      unbind_student: {
        Args: { p_admin_mode?: boolean; p_student_id: string }
        Returns: Json
      }
      update_post: {
        Args: {
          p_admin_mode?: boolean
          p_expected_version: number
          p_post: Json
          p_post_id: string
          p_request_key: string
        }
        Returns: Json
      }
      upload_complete_abort: { Args: { p_asset_id: string }; Returns: boolean }
      upload_complete_begin: {
        Args: {
          p_account_id: string
          p_batch_id: string
          p_detected_type: string
          p_item: number
          p_read_bytes: number
          p_staging_version_id: string
          p_total_bytes: number
        }
        Returns: Json
      }
      upload_complete_finish: {
        Args: { p_asset_id: string; p_checksum: string; p_version_id: string }
        Returns: Json
      }
      upload_complete_target: {
        Args: { p_batch_id: string; p_item: number }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

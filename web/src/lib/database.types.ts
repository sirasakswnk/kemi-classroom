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
      admin_remove_teacher: { Args: { p_allowlist_id: string }; Returns: Json }
      admin_teachers: { Args: never; Returns: Json }
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
      ensure_account: { Args: never; Returns: Json }
      join_classroom: { Args: { p_code: string }; Returns: Json }
      lookup_classroom: { Args: { p_code: string }; Returns: Json }
      my_classrooms: { Args: never; Returns: Json }
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
      unbind_student: {
        Args: { p_admin_mode?: boolean; p_student_id: string }
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

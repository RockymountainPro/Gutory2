//
//  Supabase.swift
//  Gutory2
//
//  Created by Mac Mantei on 2025-11-15.
//

import Foundation
import Supabase

/// Simple config so other files (like ReportsView) can reuse URL + anon key
struct SupabaseConfig {
    static let url: String = "https://yylvxtydrcbocbfcewtw.supabase.co"   // ← your URL
    static let anonKey: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl5bHZ4dHlkcmNib2NiZmNld3R3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMyMjgxNjQsImV4cCI6MjA3ODgwNDE2NH0.OcPbGn3wwQZ2cPHJf2FWGvQ4WlHvuq2qy2udrvWK3GA" // ← your anon key
}

/// Global Supabase client you can use anywhere in the app
let supabase = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.url)!,
    supabaseKey: SupabaseConfig.anonKey
)

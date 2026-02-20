//! Straylight Gateway Desktop Application
//!
//! This is a Tauri wrapper around the PureScript/Halogen dashboard,
//! providing a native desktop experience for the straylight-llm gateway.
//!
//! Part of the aleph cube architecture - proof-carrying code.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

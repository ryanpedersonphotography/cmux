fn main() -> anyhow::Result<()> {
    if std::env::var_os("ACPMUX_TRACE_STARTUP").is_some() {
        eprintln!("acpmux-trace 01 main entry");
    }
    // A terminal's launch credential names that one terminal: this process
    // and everything it starts serve many, so it is dropped before any thread
    // exists (plans/cmux-next/identity.md section 2).
    // SAFETY: the first statement of main; no other thread runs yet.
    unsafe { std::env::remove_var(acpmux::config::LAUNCH_CREDENTIAL_ENV) };
    // Nor does any of it act as the Chief whose host started it.
    for key in acpmux::config::CHIEF_CREDENTIAL_ENV {
        // SAFETY: as above, before any thread exists.
        unsafe { std::env::remove_var(key) };
    }
    if std::env::var_os("ACPMUX_TRACE_STARTUP").is_some() {
        eprintln!("acpmux-trace 02 main env scrubbed");
    }
    acpmux::cli::entry::main(std::env::args_os().skip(1).collect(), Default::default())
}

import Foundation
import RubyCore

extension RubyDictionary {
    /// JMdict with English definitions, bundled in this module, about
    /// 35 MB. Opened the first time it's used, then shared.
    ///
    ///     ContentView()
    ///         .rubyDictionary(.jmdict)
    ///
    /// The data is under CC BY-SA 4.0, not the code's licence: apps
    /// showing it must credit the Electronic Dictionary Research and
    /// Development Group. See LICENSE.md next to the database.
    public static var jmdict: RubyDictionary { bundledJMdict }
}

// The database ships inside this module, so it's always there to open.
private let bundledJMdict = RubyDictionary(url: Bundle.module.url(forResource: "jmdict", withExtension: "sqlite")!)!

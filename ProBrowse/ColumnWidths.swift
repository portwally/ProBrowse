//
//  ColumnWidths.swift
//  ProBrowse
//
//  Shared column width state for table-like layout
//

import SwiftUI
import Combine

class ColumnWidths: ObservableObject {
    @Published var nameWidth: Double
    @Published var typeWidth: Double
    @Published var auxWidth: Double
    @Published var sizeWidth: Double
    @Published var modifiedWidth: Double
    @Published var createdWidth: Double
    
    static let leftPane = ColumnWidths(prefix: "left")
    static let rightPane = ColumnWidths(prefix: "right")
    
    private var cancellables = Set<AnyCancellable>()
    private let prefix: String
    
    private init(prefix: String) {
        self.prefix = prefix
        
        // Initialize all properties first
        let savedNameWidth = UserDefaults.standard.double(forKey: "\(prefix)_columnWidth_Name")
        self.nameWidth = savedNameWidth == 0 ? 200 : savedNameWidth
        
        let savedTypeWidth = UserDefaults.standard.double(forKey: "\(prefix)_columnWidth_Type")
        self.typeWidth = savedTypeWidth == 0 ? 60 : savedTypeWidth
        
        let savedAuxWidth = UserDefaults.standard.double(forKey: "\(prefix)_columnWidth_Aux")
        self.auxWidth = savedAuxWidth == 0 ? 80 : savedAuxWidth
        
        let savedSizeWidth = UserDefaults.standard.double(forKey: "\(prefix)_columnWidth_Size")
        self.sizeWidth = savedSizeWidth == 0 ? 100 : savedSizeWidth
        
        let savedModifiedWidth = UserDefaults.standard.double(forKey: "\(prefix)_columnWidth_Modified")
        self.modifiedWidth = savedModifiedWidth == 0 ? 120 : savedModifiedWidth
        
        let savedCreatedWidth = UserDefaults.standard.double(forKey: "\(prefix)_columnWidth_Created")
        self.createdWidth = savedCreatedWidth == 0 ? 120 : savedCreatedWidth
        
        // Now set up observers
        setupObservers()
    }
    
    private func setupObservers() {
        $nameWidth.sink { UserDefaults.standard.set($0, forKey: "\(self.prefix)_columnWidth_Name") }.store(in: &cancellables)
        $typeWidth.sink { UserDefaults.standard.set($0, forKey: "\(self.prefix)_columnWidth_Type") }.store(in: &cancellables)
        $auxWidth.sink { UserDefaults.standard.set($0, forKey: "\(self.prefix)_columnWidth_Aux") }.store(in: &cancellables)
        $sizeWidth.sink { UserDefaults.standard.set($0, forKey: "\(self.prefix)_columnWidth_Size") }.store(in: &cancellables)
        $modifiedWidth.sink { UserDefaults.standard.set($0, forKey: "\(self.prefix)_columnWidth_Modified") }.store(in: &cancellables)
        $createdWidth.sink { UserDefaults.standard.set($0, forKey: "\(self.prefix)_columnWidth_Created") }.store(in: &cancellables)
    }
}

//
//  ColumnWidths.swift
//  ProBrowse
//
//  Shared column width state for table-like layout
//

import SwiftUI

class ColumnWidths: ObservableObject {
    @AppStorage("columnWidth_Name") var nameWidth: Double = 200
    @AppStorage("columnWidth_Type") var typeWidth: Double = 60
    @AppStorage("columnWidth_Aux") var auxWidth: Double = 80
    @AppStorage("columnWidth_Size") var sizeWidth: Double = 100
    @AppStorage("columnWidth_Modified") var modifiedWidth: Double = 120
    @AppStorage("columnWidth_Created") var createdWidth: Double = 120
    
    static let shared = ColumnWidths()
}

/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
*/

/**
 * Encapsulates all Ocr operation configuration options.
 */
var OcrOptions = function () {
    // Upper limit of videos user can record. Value must be equal or greater than 1.
    this.dictionary = "[]";
    // Country name to use to determine the address for Service Address when no value is determined from keywords
    this.country = "Australia";

    // Debug mode or not
    this.debug = false;
};

module.exports = OcrOptions;

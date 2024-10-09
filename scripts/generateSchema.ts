/*
 * SPDX-License-Identifier: LicenseRef-AllRightsReserved
 *
 * License-Url: https://github.com/beramarket/torchbearer/LICENSES/LicenseRef-AllRightsReserved.txt
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes KraToken III <detroitmetalcrypto@gmail.com>
 *
 * SPDX-FileContributor: Johannes KraToken III <detroitmetalcrypto@gmail.com>
 */
import * as fs from "fs"
import * as path from "path"

import { LICENSE_BLOCK } from "./constants"

const DEFAULT_SCHEMA_DIR = "./schema" // Default directory to look for .graphql files
const OUTPUT_FILE = "schema.graphql" // Name of the output schema file

// The comment block to include only once

function removeLicenseBlock(content: string): string {
  const lines = content.split("\n")
  const firstNonCommentLineIndex = lines.findIndex(
    (line) => !line.startsWith("#") && line.trim() !== "",
  )
  return lines.slice(firstNonCommentLineIndex).join("\n")
}

function ensureTrailingNewline(content: string): string {
  return content.endsWith("\n") ? content : `${content}\n`
}

function collateGraphQLSchemas(dir: string): string {
  let mergedSchema = ""

  const files = fs.readdirSync(dir)

  // Check if index.graphql exists and process it first
  const indexFile = files.find((file) => file === "index.graphql")
  if (indexFile) {
    const indexFilePath = path.join(dir, indexFile)
    let schemaContent = fs.readFileSync(indexFilePath, "utf-8")
    schemaContent = removeLicenseBlock(schemaContent)
    mergedSchema += ensureTrailingNewline(schemaContent)
  }

  // Process other .graphql files in the current directory
  files
    .filter(
      (file) =>
        file !== "index.graphql" &&
        fs.statSync(path.join(dir, file)).isFile() &&
        file.endsWith(".graphql"),
    )
    .forEach((file) => {
      const filePath = path.join(dir, file)
      let schemaContent = fs.readFileSync(filePath, "utf-8")
      schemaContent = removeLicenseBlock(schemaContent)
      mergedSchema += ensureTrailingNewline(schemaContent)
    })

  // Process subdirectories
  files
    .filter((file) => fs.statSync(path.join(dir, file)).isDirectory())
    .forEach((subDir) => {
      mergedSchema += collateGraphQLSchemas(path.join(dir, subDir))
    })

  return mergedSchema
}

function generateSchemaFile(
  schemaDir: string = DEFAULT_SCHEMA_DIR,
  outputFile: string = OUTPUT_FILE,
): void {
  const mergedSchema = LICENSE_BLOCK + collateGraphQLSchemas(schemaDir).trim()
  fs.writeFileSync(path.join("", outputFile), mergedSchema, "utf-8")
  console.log(`Schema generated successfully as ${outputFile}`)
}

generateSchemaFile()

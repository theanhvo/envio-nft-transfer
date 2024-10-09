/* eslint-disable prefer-template */
import * as fs from "fs"
import * as path from "path"

import { JAVASCRIPT_LICENSE_BLOCK } from "./constants"
import { parseGraphQLType, parseObjectFromGraphql } from "./parseObjectFromGraphql"

const INPUT_FILE = "./schema.graphql" // Default directory to look for .graphql files
const OUTPUT_FILE = "generatedEntities.ts" // Name of the output schema file

function extractTypesFromFile(graphqlFilePath: string): string[] {
  const fileContent = fs.readFileSync(graphqlFilePath, "utf-8")
  const typeDefs = fileContent.split(/type/).slice(1)
  return typeDefs.map((def) => `type ${def.split("}")[0].trim()}`)
}

function generateTypesFromFile(graphqlFilePath: string, outputFilePath: string): void {
  const typeDefinitions = extractTypesFromFile(graphqlFilePath)
  const generatedContent =
    JAVASCRIPT_LICENSE_BLOCK +
    `/* eslint-disable typescript-sort-keys/interface */\n` +
    typeDefinitions
      .map((typeDef) => {
        const typeNameMatch = typeDef.match(/type\s+(\w+)/)
        if (typeNameMatch) {
          const typeName = typeNameMatch[1]
          const fields = parseGraphQLType(typeDef)
          return parseObjectFromGraphql(typeName, fields)
        }
        return ""
      })
      .join("\n")

  fs.writeFileSync(outputFilePath, generatedContent, "utf-8")
  console.log(`Generated types and initial objects written to ${outputFilePath}`)
}

generateTypesFromFile(path.join("", INPUT_FILE), path.join("", OUTPUT_FILE))

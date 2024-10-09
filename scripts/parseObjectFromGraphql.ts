type GraphQLField = {
  isArray: number
  isDerived: boolean
  isEntity: boolean
  isNonNull: boolean
  name: string
  type: string
}

function toScreamingSnakeCase(str: string): string {
  return str.replace(/([a-z])([A-Z])/g, "$1_$2").toUpperCase()
}

export function parseGraphQLType(typeDef: string): GraphQLField[] {
  const lines = typeDef
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#") && !line.startsWith("type ") && line !== "};")

  return lines
    .map((line) => {
      const [name, rawType] = line.split(":").map((part) => part.trim().split(" ")[0]) // Remove comments

      // Handle array of arrays and nested arrays correctly
      const arrayMatches = rawType.match(/^\[+/)
      const isArray = arrayMatches ? arrayMatches[0].length : 0
      let match = ""
      if (arrayMatches) {
        match = rawType.slice(isArray, rawType.indexOf("]"))
      }
      let type = isArray ? match : rawType
      const isNonNull = rawType.endsWith("!")
      if (isNonNull) {
        type = type.slice(0, -1)
      }

      const isEntity = ![
        "ID",
        "String",
        "Int",
        "Float",
        "Boolean",
        "Bytes",
        "BigInt",
        "BigDecimal",
      ].includes(type)

      return {
        name,
        type,
        isNonNull,
        isEntity,
        isArray,
      }
    })
    .filter(Boolean) as GraphQLField[]
}

function parseInitialValue(field: GraphQLField): string {
  let value: string
  switch (field.type) {
    case "ID":
    case "String":
    case "Bytes":
      value = `""`
      break
    case "Int":
    case "Float":
      value = `0`
      break
    case "Boolean":
      value = `false`
      break
    case "BigInt":
      value = `0n`
      break
    case "BigDecimal":
      value = `BigDecimal("0")`
      break
    default:
      value = `""`
  }

  if (field.isArray) {
    return `[]`
  }

  return field.isNonNull ? value : `undefined`
}

function parseFieldType(field: GraphQLField): string {
  let fieldType: string

  switch (field.type) {
    case "ID":
    case "String":
    case "Bytes":
      fieldType = "string"
      break
    case "Int":
    case "Float":
      fieldType = "number"
      break
    case "Boolean":
      fieldType = "boolean"
      break
    case "BigInt":
      fieldType = "bigint"
      break
    case "BigDecimal":
      fieldType = "BigDecimal"
      break
    default:
      fieldType = "string" // For entity references
  }

  return `${fieldType}${`[]`.repeat(field.isArray)}`
}

export function parseObjectFromGraphql(typeName: string, fields: GraphQLField[]): string {
  const screamingSnakeCaseName = toScreamingSnakeCase(typeName)
  const constName = `INITIAL_${screamingSnakeCaseName}`

  let typeString = `type ${typeName} = {\n`
  let objectString = `export const ${constName}: ${typeName} = {\n`

  fields.forEach((field) => {
    const fieldName = field.isEntity ? `${field.name}_id` : field.name
    if (!(field.isEntity && field.isArray)) {
      const fieldType = parseFieldType(field)

      if (field.type === "ID" || !field.isEntity) {
        typeString += `  ${field.name}: ${field.isNonNull ? fieldType : `${fieldType} | undefined`}\n`
        objectString += `  ${field.name}: ${parseInitialValue(field)},\n`
      } else {
        typeString += `  ${fieldName}: ${field.isNonNull ? fieldType : `${fieldType} | undefined`}\n`
        objectString += `  ${fieldName}: ${parseInitialValue(field)},\n`
      }
    }
  })

  typeString += "}\n"
  objectString += `} satisfies ${typeName}\n`

  return `${typeString}\n${objectString}`
}

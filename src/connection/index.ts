import dotenv from "dotenv";
import { RabbitMqService } from "../utils/rabbitMQ";

dotenv.config()


const rabbitMqUrl = process.env["RABBITMQ_URL"] as string
const rabbitMqService = new RabbitMqService(rabbitMqUrl)


const connectRabbitMq = (async () => {
  try {
    await rabbitMqService.connect()
    console.log("RabbitMQ connected successfully")
  } catch (error) {
    console.error("Failed to connect to RabbitMQ:", error)
    process.exit(1)
  }
})()

export { rabbitMqService, connectRabbitMq }

import * as amqp from "amqplib"
import dotenv from "dotenv"

dotenv.config()

// Method to send a message to a specific exchange and queue
export interface SendMessageParams {
  exchange: string
  routingKey: string
  message: any
}

export class RabbitMqService {
  private connection: amqp.Connection | null = null
  private channel: amqp.Channel | null = null
  private url: string

  constructor(url: string) {
    this.url = url
  }

  // Method to connect to RabbitMQ server
  async connect() {
    if (this.connection) {
      // Nếu đã có kết nối, chỉ trả về kết nối hiện tại
      console.log("RabbitMQ already connected")
      return
    }

    try {
      console.log("Connecting to RabbitMQ...", this.url)
      this.connection = await amqp.connect(this.url)
      this.channel = await this.connection.createChannel()
      console.log("RabbitMQ connection established")
    } catch (error) {
      console.error("Failed to connect to RabbitMQ:", error)
      throw error
    }
  }

  // Private method to create message buffer with custom JSON stringify
  private createMessageBuffer(message: any): Buffer {
    return Buffer.from(
      JSON.stringify(message, (key, value) =>
        typeof value === "bigint" ? value.toString() : value,
      ),
    )
  }

  // Method to send a message to a specific exchange and queue
  async sendMessageToExchange({ exchange, routingKey, message }: SendMessageParams) {
    if (!this.channel) {
      throw new Error("RabbitMQ channel is not initialized. Call connect() first.")
    }
    try {
      // Declare the exchange (type: topic or direct based on your use case)
      await this.channel.assertExchange(exchange, "topic", { durable: true })

      const messageBuffer = this.createMessageBuffer(message)

      await this.channel.publish(exchange, routingKey, messageBuffer)

      // console.log(
      //   ` [x] Sent message to exchange "${exchange}" with routing key "${routingKey}":`,
      //   message,
      // )
    } catch (error) {
      console.error("Failed to send message to RabbitMQ:", error)
      throw error
    }
  }

  // Method to close the connection
  async closeConnection() {
    if (this.connection) {
      await this.channel?.close()
      await this.connection.close()
      console.log("RabbitMQ connection closed")
    }
  }
}

import { IsNotEmpty, IsString } from 'class-validator';

export class SsoCreateAccountDto {
  @IsNotEmpty()
  @IsString()
  token: string;
}
